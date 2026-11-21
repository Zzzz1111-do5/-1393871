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

  local refresh
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
    local f = S.focus or S.mods.era
    infoT.Text = T("gar.opt." .. f)
    infoD.Text = T("gar.d." .. f)
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
      local wp = slotPoint(b:GetAttribute("Slot"))
      local lp = wp and vcam.CFrame:PointToObjectSpace(wp)
      if lp and lp.Z < -0.5 then
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
        S.focus = S.mods[slot]
        refresh(false)
      end)
      table.insert(spotBtns, b)
    end
    refresh(true)
    return true
  end
  G.garageOpen = function() return S ~= nil end   -- 测试用
  G.garageState = function() return S end
end

return Garage
