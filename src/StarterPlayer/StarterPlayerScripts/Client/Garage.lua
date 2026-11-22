-- Roblox全面大战场（客户端）——坦克改装界面（用户 11-19：可以改坦克，像给飞机选导弹那样选装）
--   召唤地面载具时选了有改装的坦克（TankMods.FOR）先进这里：全屏暗底，中间是 3D 的坦克（VehModels 按现在选的改装拼：发射器、雷达板、
--   加特林、补贴的爆反块都看得见；拖动转视角、滚轮 / 双指缩放，不动时自己慢慢转）；模型上每个改装位一个白圈（爆反、主动防御、车顶武器），
--   点白圈或左边的卡片展开这一位能选的，点哪个装哪个、模型马上换；右下是选中那一项的说明和车速；底部「返回」「出车」
--   G.openGarage(id, mods, onSpawn)：mods 上次选的（{ aps = "hk", roof = "gau8" }），出车时 onSpawn(新的 mods)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Garage = {}

function Garage.init(G)
  local TM = require(RS:WaitForChild("TankMods"))
  local VD = require(RS:WaitForChild("VehDefs"))
  local VM = require(script.Parent:WaitForChild("VehModels"))
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local UD2 = UDim2.new
  local me = Players.LocalPlayer
  local ui = G.ui
  local function T(k, ...) return G.T(k, ...) end
  local TEXT, MUTE, ACC = RGB(236, 240, 238), RGB(150, 158, 160), RGB(126, 232, 150)

  local gui = Instance.new("ScreenGui")
  gui.Name = "Garage"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 20
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")

  local bg = ui.frame(gui, UDim2.fromScale(1, 1), nil, RGB(6, 8, 10), 0)
  bg.Active = true
  local grad = Instance.new("UIGradient")   -- 中间亮一点、四周暗（像车库里一盏顶灯）
  grad.Color = ColorSequence.new(RGB(30, 36, 40), RGB(4, 5, 6))
  grad.Rotation = 90
  grad.Parent = bg
  local modal = Instance.new("TextButton")   -- 第一人称时放开鼠标（同 Hangar.lua）
  modal.Text, modal.Size, modal.BackgroundTransparency, modal.AutoButtonColor, modal.Modal = "", UDim2.fromOffset(1, 1), 1, false, true
  modal.Parent = gui

  local vp = Instance.new("ViewportFrame")
  vp.Size = UDim2.fromScale(1, 1)
  vp.BackgroundTransparency = 1
  vp.Ambient = RGB(150, 156, 164)
  vp.LightColor = RGB(255, 250, 240)
  vp.LightDirection = V(-0.5, -1, -0.35)
  vp.Parent = bg
  local world = Instance.new("WorldModel")
  world.Parent = vp
  local vcam = Instance.new("Camera")
  vcam.FieldOfView = 34
  vcam.Parent = vp
  vp.CurrentCamera = vcam
  -- 地面：一块暗色的圆台，车停在上面
  local floor = Instance.new("Part")
  floor.Shape = Enum.PartType.Cylinder
  floor.Size = V(0.4, 44, 44)
  floor.CFrame = CF(0, -0.2, 0) * CFrame.Angles(0, 0, math.pi / 2)
  floor.Color, floor.Material, floor.Anchored = RGB(26, 30, 32), Enum.Material.Concrete, true
  floor.Parent = world

  local function square(x) for _, c in ipairs(x:GetChildren()) do if c:IsA("UICorner") then c:Destroy() end end return x end
  local title = ui.label(bg, "", UDim2.fromOffset(640, 30), UD2(0.5, 0, 0, 24), 24, TEXT, Enum.Font.GothamBlack, Vector2.new(0.5, 0))
  local sub = ui.label(bg, T("gar.sub"), UDim2.fromOffset(640, 18), UD2(0.5, 0, 0, 58), 13, MUTE, Enum.Font.GothamMedium, Vector2.new(0.5, 0))
  -- 左边：三个改装位
  local left = ui.frame(bg, UDim2.fromOffset(330, 470), UD2(0, 36, 0.5, 0), RGB(0, 0, 0), 1, Vector2.new(0, 0.5))
  local lay = Instance.new("UIListLayout")
  lay.Padding = UDim.new(0, 6)
  lay.SortOrder = Enum.SortOrder.LayoutOrder
  lay.Parent = left
  -- 右下：说明
  local info = ui.frame(bg, UDim2.fromOffset(380, 150), UD2(1, -36, 1, -100), RGB(10, 12, 14), 0.12, Vector2.new(1, 1))
  ui.stroke(info, RGB(255, 255, 255), 1, 0.88)
  local infoT = ui.label(info, "", UD2(1, -28, 0, 22), UDim2.fromOffset(14, 12), 16, TEXT, Enum.Font.GothamBold)
  local infoD = ui.label(info, "", UD2(1, -28, 0, 78), UDim2.fromOffset(14, 40), 13, RGB(196, 204, 206), Enum.Font.Gotham)
  infoD.TextWrapped, infoD.TextYAlignment = true, Enum.TextYAlignment.Top
  local infoS = ui.label(info, "", UD2(1, -28, 0, 18), UD2(0, 14, 1, -28), 13, ACC, Enum.Font.GothamBold)
  local backBtn = square(ui.button(bg, T("gar.back"), UDim2.fromOffset(150, 44), UD2(1, -236, 1, -36), RGB(30, 34, 38), Vector2.new(1, 1)))
  local goBtn = square(ui.button(bg, T("gar.spawn"), UDim2.fromOffset(180, 44), UD2(1, -36, 1, -36), RGB(52, 150, 78), Vector2.new(1, 1)))
  goBtn.Name, backBtn.Name = "GarageGo", "GarageBack"
  goBtn.Font, backBtn.Font = Enum.Font.GothamBlack, Enum.Font.GothamBold
  goBtn.TextSize, backBtn.TextSize = 17, 15
  ui.stroke(backBtn, RGB(255, 255, 255), 1, 0.8)
  local spots = ui.frame(bg, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)

  local S = nil   -- 打开时：{ id, d, mods, team, onSpawn, M, yaw, pitch, dist, tYaw, …, open（展开的改装位）, focus（说明里显示哪一项） }
  local spotBtns = {}

  -- 静止的样子：炮塔朝前、炮平着
  local function pose(M, d)
    local tp = M.tpiv or (d.turret and d.turret.pivot) or V()
    local tF = CF(tp)
    local gF = tF * CF(M.gpiv or (d.gun and d.gun.pivot) or V())
    local rF = M.rpiv and (tF * CF(M.rpiv)) or tF
    local rgF = (M.rpiv and M.rgpiv) and (rF * CF(M.rgpiv)) or rF
    local kF = M.kpiv and (tF * CF(M.kpiv)) or tF
    for _, it in ipairs(M.parts) do
      local p, grp, off, idx = it[1], it[2], it[3], it[4]
      local cf
      if grp == "turret" then cf = tF * off
      elseif grp == "gun" then cf = gF * off
      elseif grp == "rws" then cf = rF * off
      elseif grp == "rwg" then cf = rgF * off
      elseif grp == "kit" then cf = kF * off
      elseif grp == "wheel" then
        local w = M.wheels[idx]
        cf = w and (CF(w.x, w.r, w.z) * off) or off
      else cf = off end
      p.CFrame = cf
    end
  end

  -- 每个改装位在模型上的点（白圈）：爆反——首上那一片；主动防御——左边的发射器；车顶武器——炮塔顶左侧
  local function slotPoint(slot)
    local L = S and S.M and S.M.eraL
    if not L then return nil end
    if slot == "era" then
      local best = nil
      for _, b in ipairs(L.b) do
        if not best or b[4] < best[4] then best = b end   -- 最靠前的一块
      end
      return best and V(best[2], best[3], best[4]) or nil
    elseif slot == "aps" then
      local a = L.aps and L.aps.l and L.aps.l[1]
      return a and V(a[1], a[2] + 0.4, a[3]) or nil
    elseif slot == "roof" then
      return TM.kitPivot(L)
    end
  end

  -- 爆反分区（用户 11-22：「坦克我能选择在哪个地方贴爆反」）：这一区块的中心（白圈放这里）、装 / 拆
  local function zonePoint(z)
    local L = S and S.M and S.M.eraL
    if not L then return nil end
    local sum, n = V(), 0
    for _, b in ipairs(L.b) do
      if b[17] == z then sum += V(b[2], b[3], b[4]) n += 1 end
    end
    return n > 0 and sum / n or nil
  end
  local refresh
  local function toggleZone(z)
    if not S then return end
    local list, own = TM.eraZones(S.id)
    if own[z] then return end
    local on = TM.eraSet(S.mods.era, S.id)
    on[z] = not on[z]
    local out = {}
    for _, q in ipairs(list) do if on[q] or own[q] then table.insert(out, q) end end
    S.mods.era = (#out > 0) and table.concat(out, "+") or "none"
    S.mods = TM.clean(S.id, S.mods)
    S.focus, S.open = "era", "era"
    refresh(true)
  end
  G.garageToggleZone = toggleZone   -- 测试用
  local function choose(slot, opt)
    if not S then return end
    S.mods[slot] = opt
    S.mods = TM.clean(S.id, S.mods)
    S.focus = opt
    refresh(true)
  end

  local cards = {}
  local function card(text, sub2, h, color, order)
    local b = square(ui.button(left, "", UDim2.fromOffset(330, h), nil, color or RGB(20, 24, 28)))
    b.LayoutOrder = order
    b.AutoButtonColor = true
    ui.stroke(b, RGB(255, 255, 255), 1, 0.88)
    local t1 = ui.label(b, text, UD2(1, -24, 0, 20), UDim2.fromOffset(12, 8), 15, TEXT, Enum.Font.GothamBold)
    local t2 = ui.label(b, sub2 or "", UD2(1, -24, 0, 16), UDim2.fromOffset(12, h - 24), 12, ACC, Enum.Font.GothamMedium)
    t1.TextXAlignment, t2.TextXAlignment = Enum.TextXAlignment.Left, Enum.TextXAlignment.Left
    table.insert(cards, b)
    return b, t1, t2
  end

  refresh = function(remodel)
    if not S then return end
    local d = S.d
    if remodel then
      if S.M then S.M.model:Destroy() end
      S.M = VM.build(d, S.team, S.mods)
      pose(S.M, d)
      S.M.model.Parent = world
    end
    for _, c in ipairs(cards) do c:Destroy() end
    cards = {}
    local F = TM.FOR[S.id]
    local order = 0
    for _, slot in ipairs(TM.SLOTS) do
      if slot == "era" then   -- 爆反：每个区一个开关
        local zl, own = TM.eraZones(S.id)
        local on = TM.eraSet(S.mods.era, S.id)
        local names = {}
        for _, z in ipairs(zl) do if on[z] then table.insert(names, T("gar.zone." .. z)) end end
        order += 1
        local eb = card(T("gar.slot.era"), (#names > 0) and table.concat(names, " · ") or T("gar.opt.none"), 56, (S.open == "era") and RGB(26, 44, 32) or nil, order)
        eb.Activated:Connect(function()
          if not S then return end
          S.open = (S.open == "era") and nil or "era"
          S.focus = "era"
          refresh(false)
        end)
        if S.open == "era" then
          for _, z in ipairs(zl) do
            order += 1
            local sel = on[z] == true
            local zb, t1 = card("    " .. T("gar.zone." .. z), own[z] and T("gar.zoneOwn") or (sel and T("gar.zoneOn") or T("gar.zoneOff")), 44,
              sel and RGB(40, 98, 54) or RGB(14, 17, 20), order)
            zb.Name = "Zone_" .. z
            t1.TextColor3 = sel and RGB(255, 255, 255) or RGB(206, 212, 214)
            if not own[z] then zb.Activated:Connect(function() toggleZone(z) end) end
          end
        end
      else
      local list = F[slot] or {}
      local cur = S.mods[slot]
      local fixed = #list <= 1
      order += 1
      local b = card(T("gar.slot." .. slot), (fixed and (T("gar.fixed") .. " · ") or "") .. T("gar.opt." .. cur), 56, (S.open == slot) and RGB(26, 44, 32) or nil, order)
      b.Activated:Connect(function()
        if not S then return end
        S.open = (S.open == slot) and nil or slot
        S.focus = cur
        refresh(false)
      end)
      if S.open == slot and not fixed then
        for _, opt in ipairs(list) do
          order += 1
          local sel = opt == cur
          local ob, t1 = card("    " .. T("gar.opt." .. opt), "", 34, sel and RGB(40, 98, 54) or RGB(14, 17, 20), order)
          t1.TextColor3 = sel and RGB(255, 255, 255) or RGB(206, 212, 214)
          ob.Activated:Connect(function() choose(slot, opt) end)
        end
      end
      end
    end
    local f = S.focus or "era"
    if f == "era" then
      infoT.Text = T("gar.slot.era")
      infoD.Text = T("gar.d.eraZones")
    else
      infoT.Text = T("gar.opt." .. f)
      infoD.Text = T("gar.d." .. f)
    end
    local dd = TM.applyDef(d, S.mods)
    infoS.Text = T("gar.speed", math.floor(dd.speed / 2.8 * 3.6 + 0.5))
    title.Text = T("gar.title") .. "  ·  " .. T("veh." .. S.id)
  end

  local function close()
    if S and S.M then S.M.model:Destroy() end
    S = nil
    for _, b in ipairs(spotBtns) do b:Destroy() end
    spotBtns = {}
    gui.Enabled = false
  end

  backBtn.Activated:Connect(close)
  goBtn.Activated:Connect(function()
    if not S then return end
    local fn, mods = S.onSpawn, table.clone(S.mods)
    close()
    if fn then fn(mods) end
  end)

  -- 拖动转视角、滚轮缩放
  local drag, lastPos = false, nil
  bg.InputBegan:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
      drag, lastPos = true, io.Position
      if S then S.idle = 0 end
    end
  end)
  UIS.InputEnded:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then drag = false end
  end)
  UIS.InputChanged:Connect(function(io)
    if not S then return end
    if drag and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) and lastPos then
      local dlt = io.Position - lastPos
      lastPos = io.Position
      S.tYaw -= dlt.X * 0.01
      S.tPitch = math.clamp(S.tPitch + dlt.Y * 0.006, math.rad(-5), math.rad(60))
      S.idle = 0
    elseif io.UserInputType == Enum.UserInputType.MouseWheel then
      S.tDist = math.clamp(S.tDist * (1 - io.Position.Z * 0.1), S.size * 0.9, S.size * 3)
    end
  end)

  RunService.RenderStepped:Connect(function(dt)
    if not S then return end
    S.idle = (S.idle or 0) + dt
    if S.idle > 3 and not drag then S.tYaw += dt * 0.25 end   -- 不动时自己慢慢转
    local k = math.min(1, dt * 8)
    S.yaw += (S.tYaw - S.yaw) * k
    S.pitch += (S.tPitch - S.pitch) * k
    S.dist += (S.tDist - S.dist) * k
    local c = V(0, S.d.H * 0.45, 0)
    local dir = V(math.sin(S.yaw) * math.cos(S.pitch), math.sin(S.pitch), math.cos(S.yaw) * math.cos(S.pitch))
    vcam.CFrame = CFrame.lookAt(c + dir * S.dist, c)
    -- 白圈跟着模型上的点（同 Hangar.lua 的 project：界面铺满整屏、不让顶栏，框的大小就是屏幕大小）
    local vs = workspace.CurrentCamera.ViewportSize
    local tanY = math.tan(math.rad(vcam.FieldOfView) / 2)
    for _, b in ipairs(spotBtns) do
      local zk = b:GetAttribute("Zone")
      local wp
      if zk then wp = (S.open == "era") and zonePoint(zk) or nil else wp = slotPoint(b:GetAttribute("Slot")) end
      local lp = wp and vcam.CFrame:PointToObjectSpace(wp)
      if zk and lp and lp.Z < -0.5 then   -- 爆反分区的白圈：装了的实心绿、没装的空心
        local nx = lp.X / (-lp.Z * tanY * (vs.X / math.max(vs.Y, 1)))
        local ny = lp.Y / (-lp.Z * tanY)
        b.Visible = true
        b.Position = UDim2.fromOffset((nx + 1) / 2 * vs.X, (1 - ny) / 2 * vs.Y)
        local on = TM.eraSet(S.mods.era, S.id)[zk]
        b.Size = UDim2.fromOffset(22, 22)
        b.BackgroundColor3 = on and ACC or RGB(255, 255, 255)
        b.BackgroundTransparency = on and 0.15 or 0.85
      elseif lp and lp.Z < -0.5 and not zk then
        local nx = lp.X / (-lp.Z * tanY * (vs.X / math.max(vs.Y, 1)))
        local ny = lp.Y / (-lp.Z * tanY)
        b.Visible = true
        b.Position = UDim2.fromOffset((nx + 1) / 2 * vs.X, (1 - ny) / 2 * vs.Y)
        local open = S.open == b:GetAttribute("Slot")
        b.Size = open and UDim2.fromOffset(30, 30) or UDim2.fromOffset(24, 24)
        b.BackgroundTransparency = open and 0.25 or 0.8
      else
        b.Visible = false
      end
    end
  end)

  function G.openGarage(id, mods, onSpawn)
    local d = VD.get(id)
    if not d or not TM.has(id) then return false end
    if S then close() end
    local size = math.max(d.L, d.W)
    S = { id = id, d = d, mods = TM.clean(id, mods), team = me:GetAttribute("Side") or "atk", onSpawn = onSpawn,
      yaw = math.rad(140), pitch = math.rad(16), dist = size * 1.7, size = size, open = "aps" }
    S.tYaw, S.tPitch, S.tDist = S.yaw, S.pitch, S.dist
    S.focus = S.mods.aps
    gui.Enabled = true
    for _, slot in ipairs(TM.SLOTS) do
      local b = Instance.new("TextButton")
      b.Text = ""
      b.AnchorPoint = Vector2.new(0.5, 0.5)
      b.BackgroundColor3 = RGB(255, 255, 255)
      b.BackgroundTransparency = 0.8
      b.BorderSizePixel = 0
      b:SetAttribute("Slot", slot)
      local cr = Instance.new("UICorner")
      cr.CornerRadius = UDim.new(1, 0)
      cr.Parent = b
      ui.stroke(b, RGB(255, 255, 255), 2, 0.1)
      b.Parent = spots
      b.Activated:Connect(function()
        if not S then return end
        S.open = slot
        S.focus = (slot == "era") and "era" or S.mods[slot]
        refresh(false)
      end)
      table.insert(spotBtns, b)
    end
    for _, z in ipairs((TM.eraZones(id))) do   -- 爆反每个区一个白圈（展开爆反那一位时显示，点一下装 / 拆）
      local b = Instance.new("TextButton")
      b.Text = ""
      b.Name = "ZoneSpot_" .. z
      b.AnchorPoint = Vector2.new(0.5, 0.5)
      b.BackgroundColor3 = RGB(255, 255, 255)
      b.BorderSizePixel = 0
      b.Visible = false
      b:SetAttribute("Zone", z)
      local cr = Instance.new("UICorner")
      cr.CornerRadius = UDim.new(1, 0)
      cr.Parent = b
      ui.stroke(b, RGB(255, 255, 255), 2, 0.1)
      b.Parent = spots
      b.Activated:Connect(function() toggleZone(z) end)
      table.insert(spotBtns, b)
    end
    refresh(true)
    return true
  end
  G.garageOpen = function() return S ~= nil end   -- 测试用
  G.garageState = function() return S end
end

return Garage
