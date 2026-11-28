-- 全面大战场（客户端）——飞机的挂载表（战雷的「挂载」窗口）
--   用户 11-28（给了战雷截图）：「飞机选挂载我还是没找到位置 你给我做成这样」——
--   · 一个窗口：标题「挂载 - 机名」，右上 ✕
--   · 左边一张表：一行一套挂载，分三组——「对空中目标」（只挂空空弹 / 副油箱的预设）、「对地面目标」（带对地弹、炸弹、火箭的预设）、
--     「自定义武器」（编组方案 #1～#3：整备里存的「我的方案」）；一列一个挂点（从左翼尖到右翼尖），格子里画这个挂点挂的东西
--     （类别的小图形 + 型号缩写 + 几枚）；每行最左写这一套挂的是什么（型号 × 枚数）。选中的那一行亮；点一行就换成它（即时存，同整备）
--   · 右边：选中这一套的清单（型号 × 枚数）和「性能参数变化」（比空挂：外挂重量、阻力、最大速度、爬升率、盘旋一圈多几秒；变差红、变好绿）
--   · 底下：「创建 / 细调」打开整备的挂载页（一个挂点一个挂点改）；自定义方案空着的那一行「存成这个方案」
--   打开：G.openLoadout(科技树键)——机库里飞机的「挂载」键、出击页左栏的「挂载表」
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local LoadoutWin = {}

function LoadoutWin.init(G)
  local TH = require(RS:WaitForChild("Theme"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local TT = require(RS:WaitForChild("TechTree"))
  local FM = nil
  pcall(function() FM = require(RS:WaitForChild("FlightModel", 5)) end)
  local me = Players.LocalPlayer
  local RGB, U2, V2 = Color3.fromRGB, UDim2, Vector2.new
  local function L(zh, en) return (G.lang == "en") and en or zh end
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local TEXT, MUTE, FAINT, GOOD, BAD, AMBER = TH.C.TEXT, TH.C.MUTE, TH.C.FAINT, TH.C.GOOD, TH.C.BAD, TH.C.WARN

  local gui = Instance.new("ScreenGui")
  gui.Name = "LoadoutWin"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 22   -- 机库（12）、出击页（13）、观战（15）上面，设置（30）下面
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  G.loadoutGui = gui   -- 测试用

  local function frame(parent, size, pos, col, tr, name)
    local f = Instance.new("Frame")
    f.Size, f.Position = size, pos or U2.new()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = col or TH.C.PANEL, tr or 0, 0
    if name then f.Name = name end
    f.Parent = parent
    return f
  end
  local function text(parent, s, size, pos, ts, col, font, xa, name)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Text, t.Size, t.Position = s or "", size, pos or U2.new()
    t.TextSize, t.TextColor3, t.Font = ts or TH.S.body, col or TEXT, font or TH.F.body
    t.TextXAlignment = xa or Enum.TextXAlignment.Left
    t.TextTruncate = Enum.TextTruncate.AtEnd
    if name then t.Name = name end
    t.Parent = parent
    return t
  end
  local function btn(parent, s, size, pos, name, primary)
    local b = Instance.new("TextButton")
    b.AutoButtonColor = false
    b.Text, b.Size, b.Position = s, size, pos or U2.new()
    b.Font, b.TextSize = primary and TH.F.title or TH.F.bold, TH.S.small
    b.TextColor3 = primary and RGB(24, 18, 8) or TEXT
    b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = primary and AMBER or TH.C.RAISE, primary and 0 or 0.1, 0
    if name then b.Name = name end
    b.Parent = parent
    TH.corner(b, 2)
    return b
  end

  local dim = frame(gui, U2.fromScale(1, 1), nil, RGB(4, 6, 8), 0.35, "Dim")
  dim.Active = true   -- 点在窗口外面不穿透到下面
  -- 外面一层按屏幕大小缩放（UIScale），里面的窗口留给 G.uiPop 弹出来（它要往窗口上挂自己的 UIScale）
  local box = frame(gui, U2.fromOffset(1180, 620), U2.fromScale(0.5, 0.5), RGB(0, 0, 0), 1, "Box")
  box.AnchorPoint = V2(0.5, 0.5)
  local fit = Instance.new("UIScale")
  fit.Parent = box
  local win = frame(box, U2.fromScale(1, 1), U2.fromScale(0.5, 0.5), RGB(18, 22, 26), 0.02, "Win")
  win.AnchorPoint = V2(0.5, 0.5)
  TH.corner(win, 2)
  TH.stroke(win)
  local title = text(win, "", U2.new(1, -80, 0, 34), U2.fromOffset(16, 6), TH.S.title, TEXT, TH.F.title, nil, "Title")
  local close = btn(win, "✕", U2.fromOffset(34, 30), U2.new(1, -42, 0, 8), "Close")
  frame(win, U2.new(1, -16, 0, 1), U2.fromOffset(8, 44), TH.C.LINE, 0.85)

  -- 左边的表（能上下滚）、右边的说明
  local TW = 860
  local tableF = Instance.new("ScrollingFrame")
  tableF.Name = "Table"
  tableF.Size, tableF.Position = U2.fromOffset(TW, 520), U2.fromOffset(10, 52)
  tableF.BackgroundTransparency, tableF.BorderSizePixel = 1, 0
  tableF.ScrollBarThickness = 5
  tableF.ScrollingDirection = Enum.ScrollingDirection.Y
  tableF.CanvasSize = U2.new()
  tableF.Parent = win
  local side = frame(win, U2.fromOffset(1180 - TW - 34, 520), U2.fromOffset(TW + 22, 52), RGB(12, 15, 18), 0.2, "Side")
  TH.corner(side, 2)
  local sideList = text(side, "", U2.new(1, -20, 0, 150), U2.fromOffset(10, 8), TH.S.small, TEXT, TH.F.body, nil, "Chosen")
  sideList.TextYAlignment = Enum.TextYAlignment.Top
  sideList.TextWrapped = true
  sideList.TextTruncate = Enum.TextTruncate.None
  local perfT = text(side, L("性能参数变化（比空挂）", "Performance change (vs clean)"), U2.new(1, -20, 0, 18), U2.fromOffset(10, 170), TH.S.small, MUTE, TH.F.bold, nil, "PerfTitle")
  local perfRows = frame(side, U2.new(1, -20, 0, 130), U2.fromOffset(10, 192), RGB(0, 0, 0), 1, "Perf")
  local note = text(side, L("* 按这一套挂载、满内油实时算", "* Computed live for this loadout, full internal fuel"), U2.new(1, -20, 0, 16), U2.fromOffset(10, 326), TH.S.tiny, FAINT, TH.F.body)
  note.TextWrapped = true
  local fine = btn(win, L("创建 / 细调（整备）", "Create / fine-tune"), U2.fromOffset(200, 30), U2.new(0, 10, 1, -40), "Fine")
  local hint = text(win, L("点一行换成这一套（即时保存）", "Click a row to use it (saved right away)"), U2.fromOffset(400, 20), U2.new(0, 222, 1, -35), TH.S.small, MUTE)

  ---------------------------------------------------------------- 数据
  local cur = nil   -- { it, a, D, cols = 挂点顺序（左翼尖 → 右翼尖） }
  local CAT = {   -- 格子里的小图形和底色（按武器类别）
    aam = { "◇", RGB(120, 60, 60) }, agm = { "➤", RGB(130, 90, 40) }, bomb = { "▼", RGB(120, 110, 40) }, rkt = { "≡", RGB(50, 80, 120) },
    tank = { "◯", RGB(70, 90, 100) }, gun = { "·", RGB(80, 80, 80) }, sam = { "◇", RGB(120, 60, 60) },
  }
  local function shortName(wid)
    local s = T("aws." .. wid)
    if s == "aws." .. wid then s = T("aw." .. wid) end
    if s == "aw." .. wid then s = wid end
    return s
  end
  local function countOf(a, i, wid)
    local s = a.st and a.st[i]
    if not s or not wid then return 0 end
    return AD.count(s, wid)
  end
  -- 一套挂载的清单（型号 × 枚数，按出现的顺序）
  local function summary(a, load)
    local order, n = {}, {}
    for i, wid in ipairs(load or {}) do
      if wid then
        if not n[wid] then n[wid] = 0 table.insert(order, wid) end
        n[wid] += countOf(a, i, wid)
      end
    end
    local parts = {}
    for _, wid in ipairs(order) do table.insert(parts, shortName(wid) .. " ×" .. n[wid]) end
    return parts, order, n
  end
  local function isAirOnly(load)
    for _, wid in ipairs(load or {}) do
      local w = wid and AD.W[wid]
      if w and w.kind ~= "aam" and w.kind ~= "tank" then return false end
    end
    return true
  end
  local function same(a, b)
    for i = 1, math.max(#(a or {}), #(b or {})) do
      if (a[i] or false) ~= (b[i] or false) then return false end
    end
    return true
  end
  -- 性能（同整备：FlightModel.loadout + perf）：比空挂的差
  local perfCache = {}
  local function perfOf(load, fuel)
    if not (FM and FM.loadout and FM.perf and cur and cur.D) then return nil end
    local key = table.concat((function() local t = {} for i, w in ipairs(load) do t[i] = w or "" end return t end)(), ",") .. "|" .. tostring(fuel)
    if perfCache[key] then return perfCache[key] end
    local ok, Lo = pcall(FM.loadout, cur.a, load, fuel, { key = cur.it.key, AD = AD })
    if not ok or not Lo or not Lo.m then return nil end
    local ok2, p = pcall(FM.perf, cur.D, Lo.m, Lo.dCD0)
    if not ok2 or not p then return nil end
    local r = { Lo = Lo, p = p }
    perfCache[key] = r
    return r
  end

  ---------------------------------------------------------------- 画表
  local rows = {}
  local selLoad = nil
  local function setPerf(load, fuel)
    for _, c in ipairs(perfRows:GetChildren()) do c:Destroy() end
    local empty = {}
    for i = 1, #(cur.a.st or {}) do empty[i] = false end
    local P1, P0 = perfOf(load, fuel), perfOf(empty, fuel)
    local y = 0
    local function line(label, v, unit, worseIfUp, fmt)
      local up = v > 0
      local col = (math.abs(v) < 1e-6) and MUTE or (((up and worseIfUp) or (not up and not worseIfUp)) and BAD or GOOD)
      local s = string.format(fmt or "%+.0f", v)
      local t = text(perfRows, s .. " " .. unit .. "  " .. label, U2.new(1, 0, 0, 18), U2.fromOffset(0, y), TH.S.small, col, TH.F.bold)
      t.Name = "Perf_" .. label
      y += 20
    end
    if P1 and P0 then
      line(L("外挂重量", "stores weight"), (P1.Lo.ext or 0) - (P0.Lo.ext or 0), L("千克", "kg"), true)
      local cd0 = (cur.D and cur.D.CD0) or 0.02
      line(L("阻力", "drag"), ((P1.Lo.dCD0 or 0) - (P0.Lo.dCD0 or 0)) / cd0 * 100, "%", true)
      line(L("最大速度", "top speed"), ((P1.p.vAB or 0) - (P0.p.vAB or 0)) * 3.6, "km/h", false)
      line(L("爬升率", "climb rate"), (P1.p.roc or 0) - (P0.p.roc or 0), "m/s", false, "%+.1f")
      local t1 = (P1.p.str or 0) > 0 and (2 * math.pi / P1.p.str) or 0
      local t0 = (P0.p.str or 0) > 0 and (2 * math.pi / P0.p.str) or 0
      line(L("盘旋一圈", "turn time"), t1 - t0, L("秒", "s"), true, "%+.1f")
    else
      text(perfRows, L("这一型没有飞行物理数据", "No flight data for this type"), U2.new(1, 0, 0, 18), U2.fromOffset(0, 0), TH.S.small, FAINT)
    end
  end
  local function setSide(load, fuel)
    local parts = summary(cur.a, load)
    sideList.Text = (#parts > 0) and table.concat(parts, "\n") or L("不挂（空挂）", "Clean (no stores)")
    setPerf(load, fuel)
  end

  local refresh   -- 下面定义
  local function apply(load, presetKey)
    if not cur then return end
    local _, _, f = G.treeAirLoad(cur.it)
    G.treeSaveLoad(cur.it.key, load, presetKey, f, true)
    refresh()
  end

  local COLW, ROWH, NAMEW = 52, 46, 250
  local function buildRows()
    for _, c in ipairs(tableF:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
    table.clear(rows)
    local a = cur.a
    local cols = cur.cols
    local nCols = #cols
    local cw = math.max(30, math.min(COLW, math.floor((TW - NAMEW - 16) / math.max(nCols, 1))))
    local y = 0
    local curL, curP = G.treeAirLoad(cur.it)
    selLoad = curL
    local function header(s)
      local h = text(tableF, s, U2.new(0, TW - 12, 0, 24), U2.fromOffset(0, y), TH.S.sub, TEXT, TH.F.bold, Enum.TextXAlignment.Center, "Group")
      y += 26
      return h
    end
    local function row(name, load, presetKey, rowName, onPick)
      local r = Instance.new("TextButton")
      r.Name = rowName
      r.AutoButtonColor = false
      r.Text = ""
      r.Size, r.Position = U2.fromOffset(NAMEW + nCols * cw + 4, ROWH - 2), U2.fromOffset(0, y)
      local on = load ~= nil and same(load, curL)
      r.BackgroundColor3, r.BackgroundTransparency, r.BorderSizePixel = on and RGB(54, 62, 72) or RGB(26, 31, 37), on and 0 or 0.25, 0
      r.Parent = tableF
      if on then
        local st = Instance.new("UIStroke")
        st.Color, st.Thickness, st.Transparency = AMBER, 1.5, 0.15
        st.Parent = r
      end
      local nm = text(r, name, U2.fromOffset(NAMEW - 12, ROWH - 4), U2.fromOffset(8, 0), TH.S.small, load and TEXT or FAINT, TH.F.body, nil, "Name")
      nm.TextWrapped = true
      nm.TextTruncate = Enum.TextTruncate.AtEnd
      for ci, si in ipairs(cols) do
        local x = NAMEW + (ci - 1) * cw
        local cell = frame(r, U2.fromOffset(cw - 2, ROWH - 6), U2.fromOffset(x, 2), RGB(34, 40, 47), 0.15, "Cell_" .. ci)
        local wid = load and load[si]
        local w = wid and AD.W[wid]
        if w then
          local c = CAT[w.kind] or CAT.gun
          cell.BackgroundColor3, cell.BackgroundTransparency = c[2], 0.15
          local g = text(cell, c[1], U2.new(1, 0, 0, 18), U2.fromOffset(0, 1), TH.S.sub, TEXT, TH.F.bold, Enum.TextXAlignment.Center, "Glyph")
          local n = countOf(a, si, wid)
          local lab = shortName(wid)
          if #lab > 7 then lab = string.sub(lab, 1, 7) end
          text(cell, lab .. ((n > 1) and ("×" .. n) or ""), U2.new(1, -2, 0, 14), U2.new(0, 1, 1, -16), 10, TEXT, TH.F.cond, Enum.TextXAlignment.Center, "Lab")
          g.TextStrokeTransparency = 0.6
        end
      end
      r.MouseButton1Click:Connect(onPick)
      rows[#rows + 1] = { r = r, load = load }
      y += ROWH
      return r
    end
    -- 预设按用途分两组
    local airP, gndP = {}, {}
    for _, pr in ipairs(a.presets or {}) do
      local load = AD.presetLoad(a, pr.key)
      table.insert(isAirOnly(load) and airP or gndP, { pr = pr, load = load })
    end
    local function pname(e)
      local parts = summary(a, e.load)
      if #parts == 0 then return L("不挂", "Clean") end
      return table.concat(parts, "，")
    end
    if #airP > 0 then
      header(L("对空中目标", "Air targets"))
      for _, e in ipairs(airP) do row(pname(e), e.load, e.pr.key, "Preset_" .. e.pr.key, function() apply(e.load, e.pr.key) end) end
    end
    if #gndP > 0 then
      header(L("对地面目标", "Ground targets"))
      for _, e in ipairs(gndP) do row(pname(e), e.load, e.pr.key, "Preset_" .. e.pr.key, function() apply(e.load, e.pr.key) end) end
    end
    -- 自定义：整备里存的「我的方案」（tree.sets[键]["1"～"3"]）
    header(L("自定义武器", "Custom"))
    local t = G.treeState and G.treeState()
    local sets = t and t.sets and t.sets[cur.it.key] or {}
    for i = 1, 3 do
      local v = sets[tostring(i)]
      local load = (type(v) == "table" and type(v.l) == "table") and AD.cleanLoad(a, v.l) or nil
      local nm = string.format(L("编组方案 #%d", "Custom #%d"), i) .. (load and "" or L("（空）", " (empty)"))
      local r = row(nm, load, nil, "Custom_" .. i, function()
        if load then
          apply(load, nil)
        elseif G.treeSaveSet then   -- 空的：把现在这一套存进来
          local l2, _, f2 = G.treeAirLoad(cur.it)
          G.treeSaveSet(cur.it.key, i, l2, f2)
          task.delay(0.2, function() if gui.Enabled then refresh() end end)
        end
      end)
      if not load then
        text(r, L("点一下：把现在这一套存成这个方案", "Click to save the current loadout here"), U2.fromOffset(nCols * cw, ROWH - 4), U2.fromOffset(NAMEW, 0), TH.S.small, FAINT, TH.F.body, Enum.TextXAlignment.Center, "SaveHere")
      end
    end
    tableF.CanvasSize = U2.fromOffset(0, y + 8)
    -- 当前这一套不在上面任何一行（整备里一个挂点一个挂点改过）：最上面加一行「当前（已改）」
    local found = false
    for _, rr in ipairs(rows) do if rr.load and same(rr.load, curL) then found = true end end
    if not found then
      for _, c in ipairs(tableF:GetChildren()) do if c:IsA("GuiObject") then c.Position = c.Position + U2.fromOffset(0, ROWH + 26) end end
      local y0 = y
      y = 0
      header(L("当前挂载（整备里改过）", "Current (customised)"))
      row(pname({ load = curL }), curL, curP, "Current", function() end)
      y = y0 + ROWH + 26
      tableF.CanvasSize = U2.fromOffset(0, y + 8)
    end
    local _, _, f = G.treeAirLoad(cur.it)
    setSide(curL, f)
  end

  refresh = function()
    if not cur then return end
    perfCache = perfCache   -- 换挂载不清缓存（同一套不重算）
    buildRows()
  end

  local function fitScale()
    local vs = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or V2(1280, 720)
    fit.Scale = math.clamp(math.min((vs.X - 40) / 1180, (vs.Y - 40) / 620), 0.5, 1.4)
  end

  function G.openLoadout(key)
    local it = type(key) == "string" and TT.get(key)
    local a = it and AD.get(it.play)
    if not a or not a.st or #a.st == 0 then
      if G.toast then G.toast(L("这一型没有挂点", "No hardpoints on this aircraft"), "info") end
      return false
    end
    local D = nil
    if FM and a.kind == "jet" then D = FM.get(a.id, it.key) or (a.like and FM.get(a.like)) or nil end
    local cols = {}
    for i in ipairs(a.st) do cols[#cols + 1] = i end
    table.sort(cols, function(i, j)   -- 从左翼尖到右翼尖（同一个横坐标，前面的先）
      local pi, pj = a.st[i].pos, a.st[j].pos
      if math.abs(pi.X - pj.X) > 1e-3 then return pi.X < pj.X end
      return pi.Z < pj.Z
    end)
    cur = { it = it, a = a, D = D, cols = cols }
    table.clear(perfCache)
    local nm = (G.lang == "en") and it.en or it.name
    title.Text = L("挂载 - ", "Loadout - ") .. tostring(nm)
    fitScale()
    gui.Enabled = true
    refresh()
    if G.uiPop and not (G.reducedMotion and G.reducedMotion()) then G.uiPop(win, 0.97, true) end
    return true
  end
  function G.closeLoadout()
    gui.Enabled = false
    cur = nil
    if G.refreshLineup then pcall(G.refreshLineup) end   -- 机库里摆的飞机按新挂载
  end
  G.loadoutOpen = function() return gui.Enabled end
  close.MouseButton1Click:Connect(G.closeLoadout)
  fine.MouseButton1Click:Connect(function()
    local it = cur and cur.it
    G.closeLoadout()
    if it and G.openWorkshop then pcall(G.openWorkshop, it, "arms") end
  end)
  UIS.InputBegan:Connect(function(io, gp)
    if gui.Enabled and io.KeyCode == Enum.KeyCode.Escape then G.closeLoadout() end
  end)
  local cam = workspace.CurrentCamera
  if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() if gui.Enabled then fitScale() end end) end
  local _ = hint
  local _2 = perfT
end

return LoadoutWin
