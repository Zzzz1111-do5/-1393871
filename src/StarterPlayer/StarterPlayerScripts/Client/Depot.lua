-- Roblox全面大战场——地图里的载具生成点（客户端）：Depots.lua 摆的终端柱
--   按语言写按键文字（「生成」+ 型号名），只给自己队的生成点开按键；柱子上方一块小牌子：型号名、类别、名额 / 冷却（G.S.vehAvail）
--   有挂点的飞机：服务器发 { op = "hangar" } → 弹出 3D 挂载界面（右下按钮是「生成」），选好发 padSpawn；每种飞机记住上次选的挂载
--   飞机、直升机的召唤位（Depots.lua 的 summon）：牌子写「召唤飞机 / 直升机」；按 E 服务器发 { op = "airPick" } → 弹出机型列表（卡片：名字、用途、
--     舰载 / 隐身 / 航炮 / 挂点数 / 内油），点一架 → 有挂点的进挂载编辑器（可以挂副油箱），选好发 padSpawn(召唤位, 挂载, 机型)
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Depot = {}

function Depot.init(G)
  local VD = require(RS:WaitForChild("VehDefs"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local SD = require(RS:WaitForChild("ShipDefs"))
  local me = Players.LocalPlayer
  local RGB = Color3.fromRGB
  local function T(k, ...) return G.T(k, ...) end
  local function defOf(id) return VD.get(id) or AD.get(id) or SD.get(id) end

  local pads = {}       -- [生成点 Model] = { prompt, bb, name, info, bar }
  local lastLoad = {}   -- [飞机型号] = 上次选的挂载
  local lastFuel = {}   -- [飞机型号] = 上次选的内油（几成）

  -- 牌子：黑色半透明底、左边一条阵营色细线、型号名（粗）、下面一行类别和名额（细、灰）
  local function sign(post, team)
    local bb = Instance.new("BillboardGui")
    bb.Name = "PadSign"
    bb.Size = UDim2.fromOffset(210, 50)
    bb.StudsOffsetWorldSpace = Vector3.new(0, 5.2, 0)
    bb.MaxDistance = 70
    bb.LightInfluence = 0
    bb.AlwaysOnTop = false
    bb.Adornee = post
    bb.Parent = post
    local f = Instance.new("Frame")
    f.Size = UDim2.fromScale(1, 1)
    f.BackgroundColor3 = RGB(8, 10, 12)
    f.BackgroundTransparency = 0.25
    f.BorderSizePixel = 0
    f.Parent = bb
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 2, 1, 0)
    bar.BackgroundColor3 = (team == "atk") and RGB(232, 84, 72) or RGB(70, 150, 240)
    bar.BorderSizePixel = 0
    bar.Parent = f
    local function txt(y, h, size, color, font)
      local l = Instance.new("TextLabel")
      l.BackgroundTransparency = 1
      l.Position = UDim2.fromOffset(12, y)
      l.Size = UDim2.new(1, -18, 0, h)
      l.TextXAlignment = Enum.TextXAlignment.Left
      l.TextSize = size
      l.TextColor3 = color
      l.Font = font
      l.TextTruncate = Enum.TextTruncate.AtEnd
      l.Parent = f
      return l
    end
    local name = txt(6, 20, 17, RGB(240, 242, 244), Enum.Font.GothamBold)
    local info = txt(28, 16, 12, RGB(150, 156, 162), Enum.Font.GothamMedium)
    return bb, name, info, bar
  end

  local function add(m)
    if pads[m] then return end
    local post = m:FindFirstChild("Post")
    local prompt = post and post:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then return end
    local bb, name, info, bar = sign(post, m:GetAttribute("Team"))
    pads[m] = { prompt = prompt, bb = bb, name = name, info = info, bar = bar }
  end

  local function pointOwner(id)
    for _, s in ipairs((G.S and G.S.points) or {}) do
      if s.id == id then return s.owner end
    end
    return nil
  end

  local folder = nil
  local function refresh()
    if not folder then
      local root = workspace:FindFirstChild("Map")
      folder = root and root:FindFirstChild("Pads")
      if folder then
        folder.ChildAdded:Connect(add)
      end
    end
    if folder then
      for _, m in ipairs(folder:GetChildren()) do if not pads[m] then add(m) end end
    end
    local S = G.S
    local side = me:GetAttribute("Side")
    for m, x in pairs(pads) do
      if not m.Parent then
        pads[m] = nil
      else
        local id = m:GetAttribute("Model")
        local d = defOf(id)
        local mine = m:GetAttribute("Team") == side
        local need = m:GetAttribute("Need") or ""
        local open = mine and (need == "" or pointOwner(need) == side)
        local summon = (m:GetAttribute("Summon") or "") ~= ""
        local title = summon and T(m:GetAttribute("Heli") and "pad.summonHeli" or "pad.summonJet") or T("veh." .. id)
        x.prompt.Enabled = mine
        x.prompt.ActionText = T(summon and "pad.summon" or "pad.spawn")
        x.prompt.ObjectText = title
        x.bb.Enabled = mine
        x.name.Text = title
        local av = S and S.vehAvail and d and S.vehAvail[d.cat]
        local st = ""
        if not open then st = T("pad.need" .. need)
        elseif av and av.u >= av.cap then st = (av.cd and av.cd > 0) and T("pad.cd", av.cd) or T("pad.full", av.u, av.cap)
        elseif av then st = T("pad.ready", av.u, av.cap) end
        x.info.Text = (d and T("vcat." .. d.cat) or "") .. "   " .. st
        x.info.TextColor3 = (open and av and av.u < av.cap) and RGB(150, 156, 162) or RGB(214, 120, 96)
      end
    end
  end
  task.spawn(function()
    while true do
      local ok, err = pcall(refresh)
      if not ok and G.showError then G.showError("local depot: " .. tostring(err)) end
      task.wait(0.5)
    end
  end)

  ---------------------------------------------------------------- 召唤位：选机型

  -- 机型的用途（卡片上的一行字）
  local ROLE = { j20 = "fighter", j35 = "fighter", j15t = "fighter", j50 = "fighter", f22 = "fighter", f35 = "fighter", j16 = "strike", a10c = "attack",
    h6k = "bomber", b2 = "bomber", gj11 = "uav", gj2 = "uav", mq9 = "uav", z10 = "aheli", ah64e = "aheli", z20 = "uheli", uh60 = "uheli", ch47 = "theli" }
  local pick = Instance.new("ScreenGui")
  pick.Name = "AirPick"
  pick.ResetOnSpawn = false
  pick.IgnoreGuiInset = true
  pick.DisplayOrder = 19
  pick.Enabled = false
  pick.Parent = me:WaitForChild("PlayerGui")
  local dim = Instance.new("Frame")
  dim.Size = UDim2.fromScale(1, 1)
  dim.BackgroundColor3 = RGB(0, 0, 0)
  dim.BackgroundTransparency = 0.4
  dim.BorderSizePixel = 0
  dim.Active = true   -- 点在这上面不算点在游戏里
  dim.Parent = pick
  local modal = Instance.new("TextButton")   -- 第一人称时放开鼠标（同挂载编辑器）
  modal.Text, modal.Size, modal.BackgroundTransparency, modal.Modal = "", UDim2.fromOffset(1, 1), 1, true
  modal.Parent = pick
  local panel = Instance.new("Frame")
  panel.Name = "Panel"
  panel.Size = UDim2.fromOffset(820, 470)
  panel.AnchorPoint = Vector2.new(0.5, 0.5)
  panel.Position = UDim2.fromScale(0.5, 0.5)
  panel.BackgroundColor3 = RGB(10, 12, 14)
  panel.BackgroundTransparency = 0.08
  panel.BorderSizePixel = 0
  panel.Parent = dim
  do
    local st = Instance.new("UIStroke")
    st.Color, st.Transparency, st.Thickness = RGB(255, 255, 255), 0.86, 1
    st.Parent = panel
    local sc = Instance.new("UIScale")
    sc.Parent = panel
    local function fit()
      local vs = workspace.CurrentCamera.ViewportSize
      sc.Scale = math.clamp(math.min(vs.X / 900, vs.Y / 540), 0.45, 1.3)
    end
    fit()
    workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
  end
  local function label(parent, text, size, pos, ts, color, font, xa)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size, l.Position = size, pos
    l.Text, l.TextSize, l.TextColor3, l.Font = text or "", ts, color, font
    l.TextXAlignment = xa or Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Parent = parent
    return l
  end
  local pTitle = label(panel, "", UDim2.new(1, -40, 0, 28), UDim2.fromOffset(24, 18), 22, RGB(240, 242, 244), Enum.Font.GothamBlack)
  local pSub = label(panel, "", UDim2.new(1, -40, 0, 16), UDim2.fromOffset(24, 50), 12, RGB(150, 156, 162), Enum.Font.GothamMedium)
  local grid = Instance.new("Frame")
  grid.Size, grid.Position = UDim2.new(1, -48, 1, -140), UDim2.fromOffset(24, 80)
  grid.BackgroundTransparency = 1
  grid.Parent = panel
  local gl = Instance.new("UIGridLayout")
  gl.CellSize, gl.CellPadding = UDim2.fromOffset(250, 104), UDim2.fromOffset(10, 10)
  gl.SortOrder = Enum.SortOrder.LayoutOrder
  gl.Parent = grid
  local cancel = Instance.new("TextButton")
  cancel.Name = "Cancel"
  cancel.Size, cancel.Position = UDim2.fromOffset(140, 38), UDim2.new(0, 24, 1, -54)
  cancel.BackgroundColor3, cancel.BackgroundTransparency, cancel.BorderSizePixel = RGB(255, 255, 255), 0.9, 0
  cancel.Font, cancel.TextSize, cancel.TextColor3 = Enum.Font.GothamBold, 15, RGB(240, 242, 244)
  cancel.Parent = panel
  local cards = {}
  local pickPad = nil
  local function closePick()
    pick.Enabled = false
    pickPad = nil
  end
  cancel.Activated:Connect(closePick)
  G.pickerOpen = function() return pick.Enabled end

  local function choose(id)
    local pad = pickPad
    closePick()
    local d = AD.get(id)
    if not d or not pad then return end
    if d.st and #d.st > 0 and G.openHangar then
      G.openHangar(id, lastLoad[id], function(load, _, fuel)
        lastLoad[id], lastFuel[id] = load, fuel
        G.R.Act:FireServer("padSpawn", pad, load, id, fuel)
      end, nil, { confirm = "pad.spawn", fuel = lastFuel[id] })
    else
      G.R.Act:FireServer("padSpawn", pad, nil, id)
    end
  end

  local function openPick(padId, ids, heli)
    for _, c in ipairs(cards) do c:Destroy() end
    cards = {}
    pickPad = padId
    pTitle.Text = T(heli and "pad.summonHeli" or "pad.summonJet")
    local S = G.S
    local av = S and S.vehAvail and S.vehAvail[heli and "heli" or "jet"]
    local st = ""
    if av then st = (av.u >= av.cap) and ((av.cd and av.cd > 0) and T("pad.cd", av.cd) or T("pad.full", av.u, av.cap)) or T("pad.ready", av.u, av.cap) end
    pSub.Text = T("pick.sub") .. "   ·   " .. st
    cancel.Text = T("pick.cancel")
    for i, id in ipairs(ids) do
      local d = AD.get(id)
      if d then
        local b = Instance.new("TextButton")
        b.Name = "Pick_" .. id
        b.Text = ""
        b.LayoutOrder = i
        b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = RGB(24, 27, 31), 0.05, 0
        b.AutoButtonColor = true
        b.Parent = grid
        local stroke = Instance.new("UIStroke")
        stroke.Color, stroke.Transparency, stroke.Thickness = RGB(255, 255, 255), 0.9, 1
        stroke.Parent = b
        b.MouseEnter:Connect(function() stroke.Transparency = 0.4 end)
        b.MouseLeave:Connect(function() stroke.Transparency = 0.9 end)
        label(b, T("veh." .. id), UDim2.new(1, -24, 0, 24), UDim2.fromOffset(12, 10), 18, RGB(240, 242, 244), Enum.Font.GothamBlack)
        label(b, T("arole." .. (ROLE[id] or (d.kind == "heli" and "uheli" or "fighter"))), UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 36), 12, RGB(214, 190, 120), Enum.Font.GothamBold)
        local tags = {}
        if d.carrier then table.insert(tags, T("pick.carrier")) end
        if d.stealth then table.insert(tags, T("pick.stealth")) end
        if d.gun then table.insert(tags, T("pick.gun")) end
        if d.st and #d.st > 0 then table.insert(tags, T("pick.st", #d.st)) end
        if AD.fuelMin then table.insert(tags, T("pick.fuel", AD.fuelMin(d))) end
        local tl = label(b, table.concat(tags, " · "), UDim2.new(1, -24, 0, 32), UDim2.fromOffset(12, 56), 12, RGB(170, 176, 182), Enum.Font.GothamMedium)
        tl.TextWrapped = true
        tl.TextTruncate = Enum.TextTruncate.None
        tl.TextYAlignment = Enum.TextYAlignment.Top
        b.Activated:Connect(function() choose(id) end)
        table.insert(cards, b)
      end
    end
    pick.Enabled = true
  end

  -- 服务器：有挂点的飞机开挂载界面（老的一型一个生成点）；召唤位先选机型
  G.R.Drive.OnClientEvent:Connect(function(d)
    if type(d) ~= "table" then return end
    if d.op == "airPick" and type(d.ids) == "table" then
      openPick(d.pad, d.ids, d.heli == true)
      return
    end
    if d.op ~= "hangar" or not G.openHangar then return end
    local id, pad = d.id, d.pad
    if not AD.get(id) then return end
    G.openHangar(id, lastLoad[id], function(load, _, fuel)
      lastLoad[id], lastFuel[id] = load, fuel
      G.R.Act:FireServer("padSpawn", pad, load, nil, fuel)
    end, nil, { confirm = "pad.spawn", fuel = lastFuel[id] })
  end)
end

return Depot
