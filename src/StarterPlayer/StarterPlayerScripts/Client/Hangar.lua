-- Roblox全面大战场（客户端）——挂载编辑器（部署界面飞机卡片上的「改挂载」）
--   全屏黑底，中间是 3D 的飞机（AirModels 拼的，放下起落架、打开弹舱，挂着现在选的弹；拖动转视角、滚轮缩放）；
--   每个挂点一个白色圆圈，点一下镜头拉近到那个挂点，左边列出这个挂点能挂的弹（名字、类别、导引方式），点哪个挂哪个（默认左右对称一起换），
--   选中的弹发白光；右下角是这枚弹的资料（类别、导引方式、射程、数量、锁定时间）；上面一排是预设方案；底部「返回」「保存」
--   G.openHangar(id, load, onSave)：load 是每个挂点的武器（同 AirDefs.presetLoad 的格式），保存时 onSave(新的 load)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Hangar = {}

function Hangar.init(G)
  local AD = require(RS:WaitForChild("AirDefs"))
  local AM = require(script.Parent:WaitForChild("AirModels"))
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local rad = math.rad
  local me = Players.LocalPlayer
  local ui = G.ui
  local function T(k, ...) return G.T(k, ...) end
  local TEXT, MUTE = RGB(240, 242, 240), RGB(160, 166, 164)

  local gui = Instance.new("ScreenGui")
  gui.Name = "Hangar"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 20
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")

  local bg = ui.frame(gui, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 0)
  local vp = Instance.new("ViewportFrame")
  vp.Size = UDim2.fromScale(1, 1)
  vp.BackgroundColor3 = RGB(0, 0, 0)
  vp.BackgroundTransparency = 1
  vp.Ambient = RGB(172, 175, 182)   -- 全景从下面看机腹：环境光亮一点，不然一片黑
  vp.LightColor = RGB(255, 252, 246)
  vp.LightDirection = V(-0.6, -1, -0.5)
  vp.Parent = bg
  local world = Instance.new("WorldModel")
  world.Parent = vp
  local vcam = Instance.new("Camera")
  vcam.FieldOfView = 40
  vcam.Parent = vp
  vp.CurrentCamera = vcam

  local spots = ui.frame(bg, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)
  local title = ui.label(bg, "", UDim2.fromOffset(520, 30), UDim2.new(0.5, 0, 0, 22), 24, TEXT, Enum.Font.GothamBlack, Vector2.new(0.5, 0))
  local hint = ui.label(bg, "", UDim2.fromOffset(620, 18), UDim2.new(0.5, 0, 0, 54), 13, MUTE, Enum.Font.GothamMedium, Vector2.new(0.5, 0))
  local presetRow = ui.frame(bg, UDim2.fromOffset(700, 34), UDim2.new(0.5, 0, 0, 80), RGB(0, 0, 0), 1, Vector2.new(0.5, 0))
  local pl = Instance.new("UIListLayout")
  pl.FillDirection = Enum.FillDirection.Horizontal
  pl.HorizontalAlignment = Enum.HorizontalAlignment.Center
  pl.Padding = UDim.new(0, 8)
  pl.Parent = presetRow
  local symBtn = ui.button(bg, "", UDim2.fromOffset(150, 34), UDim2.new(1, -24, 0, 80), RGB(30, 34, 38), Vector2.new(1, 0))
  symBtn.TextSize = 14
  -- 左边：这个挂点能挂的弹
  local listBox = ui.frame(bg, UDim2.fromOffset(370, 420), UDim2.new(0, 40, 1, -96), RGB(0, 0, 0), 1, Vector2.new(0, 1))
  local listLayout = Instance.new("UIListLayout")
  listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
  listLayout.Padding = UDim.new(0, 8)
  listLayout.SortOrder = Enum.SortOrder.LayoutOrder
  listLayout.Parent = listBox
  -- 右下：弹的资料
  local info = ui.frame(bg, UDim2.fromOffset(380, 196), UDim2.new(1, -40, 1, -96), RGB(10, 12, 14), 0.1, Vector2.new(1, 1))
  ui.round(info, 6)
  ui.stroke(info, RGB(255, 255, 255), 1, 0.85)
  local iName = ui.label(info, "", UDim2.new(1, -40, 0, 26), UDim2.fromOffset(20, 18), 19, TEXT, Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left)
  local iCat = ui.label(info, "", UDim2.new(1, -40, 0, 18), UDim2.fromOffset(20, 50), 13, MUTE, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
  local rows = {}
  for k = 1, 4 do
    local a = ui.label(info, "", UDim2.new(0.5, -20, 0, 20), UDim2.fromOffset(20, 76 + k * 24), 14, MUTE, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
    local b = ui.label(info, "", UDim2.new(0.5, -20, 0, 20), UDim2.new(0.5, 0, 0, 76 + k * 24), 14, TEXT, Enum.Font.GothamBold, nil, Enum.TextXAlignment.Right)
    rows[k] = { a, b }
  end
  local summary = ui.label(bg, "", UDim2.new(0.5, 0, 0, 18), UDim2.new(0.5, 0, 1, -112), 13, MUTE, Enum.Font.GothamMedium, Vector2.new(0.5, 1))
  local backBtn = ui.button(bg, "", UDim2.fromOffset(130, 52), UDim2.new(0.5, -8, 1, -28), RGB(0, 0, 0), Vector2.new(1, 1))
  ui.stroke(backBtn, RGB(255, 255, 255), 1, 0.7)
  backBtn.TextSize = 20
  backBtn.Font = Enum.Font.Gotham
  local saveBtn = ui.button(bg, "", UDim2.fromOffset(170, 52), UDim2.new(0.5, 8, 1, -28), RGB(255, 255, 255), Vector2.new(0, 1))
  saveBtn.TextColor3 = RGB(10, 10, 10)
  saveBtn.TextSize = 20
  saveBtn.Font = Enum.Font.Gotham

  ---------------------------------------------------------------- 状态

  local H = nil   -- { d, load, team, M, sel（选中的挂点）, sym, yaw, pitch, dist, focus, 目标值…, onSave }
  local spotBtns = {}

  local function weaponCat(w)
    if w.arm then return "wcat.arm" end
    if w.kind == "bomb" then return w.guided and "wcat.gbomb" or "wcat.bomb" end
    return "wcat." .. w.kind
  end
  local function km(studs) return string.format("%.1f", (studs or 0) / AD.M / 1000) end

  -- 选中挂点上的弹发白光（ViewportFrame 里没有高亮：把零件换成白色霓虹）
  local function glow(i)
    if not H or not H.M then return end
    for si, list in pairs(H.M.stores) do
      for _, it in ipairs(list) do
        local p = it.p
        if not it.c0 then it.c0, it.m0 = p.Color, p.Material end
        if si == i then
          p.Color = it.c0:Lerp(Color3.new(1, 1, 1), 0.65)
          p.Material = Enum.Material.Neon
        else
          p.Color, p.Material = it.c0, it.m0
        end
      end
    end
  end

  local function rebuild()
    if H.M then H.M.model:Destroy() end
    local M = AM.build(H.d, H.team, H.load)
    M.model.Parent = world
    H.M = M
    local c = { gear = 1, bay = 1, bayS = 1, can = 0, fold = 0, thr = 0, rpm = 0, flap = 0 }
    AM.pose(M, CF(), c, 0, world)
    glow(H.sel)
  end

  local function mates(i)   -- 左右成对的挂点（同名）
    local out = { i }
    local s = H.d.st[i]
    if H.sym then
      for j, s2 in ipairs(H.d.st) do if j ~= i and s2.name == s.name then table.insert(out, j) end end
    end
    return out
  end

  local function showInfo(wid, n)
    local w = wid and AD.W[wid]
    if not w then
      iName.Text = T("hangar.empty")
      iCat.Text = ""
      for _, r in ipairs(rows) do r[1].Text, r[2].Text = "", "" end
      return
    end
    iName.Text = T("aw." .. wid)
    iCat.Text = string.upper(T(weaponCat(w)))
    local data = { { T("hangar.guide"), T("guide." .. (w.guide or "none")) } }
    if w.range then table.insert(data, { T("hangar.range"), T("hangar.km", km(w.range)) }) end
    if w.kind == "rkt" then table.insert(data, { T("hangar.count"), tostring(w.tubes or 1) }) else table.insert(data, { T("hangar.count"), "×" .. tostring(n or 1) }) end
    if w.lockTime then table.insert(data, { T("hangar.lock"), T("hangar.sec", string.format("%.1f", w.lockTime)) }) end
    for k, r in ipairs(rows) do
      local e = data[k]
      r[1].Text, r[2].Text = e and e[1] or "", e and e[2] or ""
    end
  end

  local listRows = {}
  local function buildList()
    for _, b in ipairs(listRows) do b:Destroy() end
    listRows = {}
    info.Visible = H.sel ~= nil   -- 资料框只在选了挂点时出现（全景时空着一大块）
    if not H.sel then
      listBox.Visible = false
      return
    end
    listBox.Visible = true
    local s = H.d.st[H.sel]
    local opts = table.clone(s.opts)
    table.insert(opts, false)   -- 不挂
    for k, wid in ipairs(opts) do
      local on = (H.load[H.sel] or false) == wid
      local b = Instance.new("TextButton")
      b.Text = ""
      b.LayoutOrder = k
      b.Size = UDim2.new(1, 0, 0, 62)
      b.BackgroundColor3 = on and RGB(255, 255, 255) or RGB(8, 10, 12)
      b.BackgroundTransparency = on and 0 or 0.15
      b.AutoButtonColor = true
      b.Parent = listBox
      ui.round(b, 6)
      ui.stroke(b, RGB(255, 255, 255), 1, on and 0 or 0.82)
      local fg = on and RGB(16, 16, 16) or TEXT
      local w = wid and AD.W[wid]
      local n = wid and AD.count(s, wid) or 0
      local nm = wid and T("aw." .. wid) or T("hangar.empty")
      if wid and n > 1 and w.kind ~= "rkt" then nm = n .. " × " .. nm end
      local l1 = ui.label(b, nm, UDim2.new(1, -24, 0, 26), UDim2.fromOffset(16, 6), 19, fg, Enum.Font.Gotham, nil, Enum.TextXAlignment.Left)
      l1.TextTruncate = Enum.TextTruncate.AtEnd
      ui.label(b, w and T(weaponCat(w)) or "", UDim2.new(0.62, -16, 0, 18), UDim2.fromOffset(16, 36), 14, on and RGB(60, 60, 60) or MUTE, Enum.Font.Gotham, nil, Enum.TextXAlignment.Left)
      ui.label(b, w and T("guide." .. (w.guide or "none")) or "", UDim2.new(0.38, -16, 0, 18), UDim2.new(0.62, 0, 0, 36), 13, on and RGB(60, 60, 60) or MUTE, Enum.Font.Gotham, nil, Enum.TextXAlignment.Right)
      b.MouseEnter:Connect(function() if H then showInfo(wid, n) end end)
      b.Activated:Connect(function()
        if not H then return end
        for _, j in ipairs(mates(H.sel)) do
          local s2 = H.d.st[j]
          H.load[j] = (wid and table.find(s2.opts, wid)) and wid or false
        end
        H.presetKey = nil
        rebuild()
        buildList()
        showInfo(wid, n)
        G.refreshHangar()
      end)
      table.insert(listRows, b)
    end
  end

  local presetBtns = {}
  local function buildPresets()
    for _, b in ipairs(presetBtns) do b:Destroy() end
    presetBtns = {}
    for _, p in ipairs(H.d.presets or {}) do
      local b = ui.button(presetRow, T("preset." .. p.key), UDim2.fromOffset(120, 32), nil, RGB(26, 30, 34))
      b.TextSize = 14
      b.Activated:Connect(function()
        if not H then return end
        H.load = AD.presetLoad(H.d, p.key)
        H.presetKey = p.key
        rebuild()
        buildList()
        G.refreshHangar()
      end)
      presetBtns[p.key] = b
    end
  end

  local function selectStation(i)
    H.sel = i
    local s = H.d.st[i]
    -- 镜头拉近到这个挂点（从它那一侧、稍微前上方看）
    H.tFocus = s.pos + V(0, -0.8, 0)
    -- 拉近到看得见这一侧机翼和机身（照飞机大小；原来按弹的长短，拉得太近，整架飞机撑出屏幕）
    local L = (H.load[i] and AD.W[H.load[i]] and AD.W[H.load[i]].shape and AD.W[H.load[i]].shape.L) or 6
    H.tDist = math.max(math.max(H.d.L, H.d.W) * 0.85, L * 2.6 + 14)
    H.tYaw = (s.pos.X >= 0) and rad(55) or rad(-55)
    if s.bay then H.tPitch = rad(-22) else H.tPitch = rad(-12) end
    glow(i)
    buildList()
    local wid = H.load[i]
    showInfo(wid, wid and AD.count(s, wid) or 0)
    G.refreshHangar()
  end

  function G.refreshHangar()
    if not H then return end
    title.Text = T("veh." .. H.d.id)
    hint.Text = T("hangar.hint")
    symBtn.Text = T(H.sym and "hangar.symOn" or "hangar.symOff")
    backBtn.Text = T("hangar.back")
    saveBtn.Text = T("hangar.save")
    for key, b in pairs(presetBtns) do
      b.Text = T("preset." .. key)
      b.BackgroundColor3 = (H.presetKey == key) and RGB(255, 255, 255) or RGB(26, 30, 34)
      b.TextColor3 = (H.presetKey == key) and RGB(16, 16, 16) or TEXT
    end
    -- 总共挂了什么
    local count, order = {}, {}
    for i, s in ipairs(H.d.st or {}) do
      local wid = H.load[i]
      if wid then
        if not count[wid] then table.insert(order, wid) end
        count[wid] = (count[wid] or 0) + AD.count(s, wid)
      end
    end
    local parts = {}
    if H.d.gun then table.insert(parts, T("aw." .. H.d.gun)) end
    for _, wid in ipairs(order) do table.insert(parts, T("aw." .. wid) .. " ×" .. count[wid]) end
    summary.Text = table.concat(parts, "   ·   ")
    if not H.sel then showInfo(nil) iName.Text = T("hangar.pick") end
  end

  local function close()
    if H and H.M then H.M.model:Destroy() end
    H = nil
    for _, b in ipairs(spotBtns) do b:Destroy() end
    spotBtns = {}
    gui.Enabled = false
  end

  function G.openHangar(id, load, onSave, presetKey)
    local d = AD.get(id)
    if not d then return end
    if H then close() end
    local size = math.max(d.L, d.W)
    H = { d = d, load = table.clone(load or AD.presetLoad(d)), team = me:GetAttribute("Side") or "atk", onSave = onSave, sym = true, presetKey = presetKey,
      yaw = rad(-150), pitch = rad(8), dist = size * 1.5, focus = V(0, -1, 0), shift = 0 }   -- 全景从左前稍下方看：挂点都在机腹、翼下，从上面看会挤成一团
    H.tYaw, H.tPitch, H.tDist, H.tFocus = H.yaw, H.pitch, H.dist, H.focus
    H.home = { yaw = H.yaw, pitch = H.pitch, dist = H.dist, focus = H.focus }
    for i = 1, #(d.st or {}) do if H.load[i] == nil then H.load[i] = false end end
    gui.Enabled = true
    rebuild()
    buildPresets()
    -- 挂点的白圈（空心圈 + 中间一个点，不把弹盖住；选中的变黄、变大）
    for i, s in ipairs(d.st or {}) do
      local b = Instance.new("TextButton")
      b.Text = ""
      b.Size = UDim2.fromOffset(26, 26)
      b.AnchorPoint = Vector2.new(0.5, 0.5)
      b.BackgroundColor3 = RGB(255, 255, 255)
      b.BackgroundTransparency = 0.85
      b.AutoButtonColor = false
      b.ZIndex = 3
      b.Parent = spots
      local c = Instance.new("UICorner")
      c.CornerRadius = UDim.new(0.5, 0)
      c.Parent = b
      local dot = ui.frame(b, UDim2.fromOffset(6, 6), UDim2.fromScale(0.5, 0.5), RGB(255, 255, 255), 0, Vector2.new(0.5, 0.5))
      dot.Name = "Dot"
      dot.ZIndex = 4
      ui.round(dot, 3)
      local st = ui.stroke(b, RGB(255, 255, 255), 2, 0.05)
      b.Activated:Connect(function() if H then selectStation(i) end end)
      spotBtns[i] = b
      b:SetAttribute("Station", i)
      b.Name = "Spot" .. i
      st.Name = "Ring"
    end
    H.sel = nil
    buildList()
    G.refreshHangar()
  end

  symBtn.Activated:Connect(function()
    if not H then return end
    H.sym = not H.sym
    G.refreshHangar()
  end)
  backBtn.Activated:Connect(function()
    if not H then return end
    if H.sel then   -- 先退回全景，再按一次关掉
      H.sel = nil
      H.tYaw, H.tPitch, H.tDist, H.tFocus = H.home.yaw, H.home.pitch, H.home.dist, H.home.focus
      glow(nil)
      buildList()
      G.refreshHangar()
      return
    end
    close()
  end)
  saveBtn.Activated:Connect(function()
    if not H then return end
    local f, load, key = H.onSave, table.clone(H.load), H.presetKey
    close()
    if f then f(load, key) end
  end)

  ---------------------------------------------------------------- 拖动转视角、滚轮缩放

  local dragging, last = false, nil
  vp.InputBegan:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
      dragging, last = true, io.Position
    end
  end)
  UIS.InputEnded:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then dragging = false end
  end)
  UIS.InputChanged:Connect(function(io)
    if not H or not gui.Enabled then return end
    if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
      local p = io.Position
      local dx, dy = p.X - (last and last.X or p.X), p.Y - (last and last.Y or p.Y)
      last = p
      H.tYaw -= dx * 0.008
      H.tPitch = math.clamp(H.tPitch - dy * 0.006, rad(-75), rad(40))
    elseif io.UserInputType == Enum.UserInputType.MouseWheel then
      H.tDist = math.clamp(H.tDist * ((io.Position.Z > 0) and 0.88 or 1.14), 10, math.max(H.d.L, H.d.W) * 3.5)
    end
  end)

  ---------------------------------------------------------------- 每帧：镜头、白圈的位置

  local function project(p, camCF)
    local lp = camCF:PointToObjectSpace(p)
    if lp.Z > -0.5 then return nil end
    local vs = workspace.CurrentCamera.ViewportSize   -- 编辑器铺满整屏、不让顶栏（IgnoreGuiInset），框的大小就是屏幕大小
    local tanY = math.tan(rad(vcam.FieldOfView) / 2)
    local nx = lp.X / (-lp.Z * tanY * (vs.X / vs.Y))
    local ny = lp.Y / (-lp.Z * tanY)
    return UDim2.fromOffset((nx + 1) / 2 * vs.X, (1 - ny) / 2 * vs.Y)
  end
  local function step(dt)
    if not H or not gui.Enabled then return end
    local k = math.min(1, dt * 6)
    H.yaw += (H.tYaw - H.yaw) * k
    H.pitch += (H.tPitch - H.pitch) * k
    H.dist += (H.tDist - H.dist) * k
    H.focus = H.focus:Lerp(H.tFocus, k)
    if not H.sel and not dragging then H.tYaw += dt * 0.12 end   -- 全景时慢慢转
    -- 选了挂点：镜头往左挪一点，挂点落在屏幕偏右（左边是弹的列表）
    H.shift += ((H.sel and -H.dist * 0.12 or 0) - H.shift) * k
    local camCF = CF(H.focus) * CFrame.Angles(0, H.yaw, 0) * CFrame.Angles(H.pitch, 0, 0) * CF(H.shift, 0, H.dist)
    vcam.CFrame = camCF
    for i, b in pairs(spotBtns) do
      local s = H.d.st[i]
      local pos = project(s.pos + V(0, -0.6, 0), camCF)
      -- 左右对称时一对挂点只画离镜头近的那个圈（点哪个都是一对一起换），不然机腹弹舱那几个圈挤成一团
      if pos and H.sym and H.sel ~= i then
        for j, s2 in ipairs(H.d.st) do
          if j ~= i and s2.name == s.name and (H.sel == j or (H.sel ~= i and (s2.pos - camCF.Position).Magnitude < (s.pos - camCF.Position).Magnitude - 0.01)) then
            pos = nil
            break
          end
        end
      end
      b.Visible = pos ~= nil
      if pos then b.Position = pos end
      local on = H.sel == i
      b.Size = on and UDim2.fromOffset(36, 36) or UDim2.fromOffset(26, 26)
      local ring = b:FindFirstChild("Ring")
      if ring then
        ring.Color = on and RGB(255, 210, 60) or RGB(255, 255, 255)
        ring.Thickness = on and 3 or 2
        ring.Transparency = (on or not H.sel) and 0.05 or 0.55   -- 选了一个挂点时别的圈淡一点
      end
      b.BackgroundTransparency = on and 0.6 or 0.85
    end
  end
  RunService.RenderStepped:Connect(function(dt)
    local ok, err = pcall(step, dt)
    if not ok and G.showError then G.showError("local hangar: " .. tostring(err)) end
  end)
  G.hangarOpen = function() return H ~= nil end
  G.hangarState = function() return H end
end

return Hangar
