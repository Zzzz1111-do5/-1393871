-- Roblox全面大战场——地图里的载具生成点（客户端）：Depots.lua 摆的终端柱
--   按语言写按键文字（「生成」+ 型号名），只给自己队的生成点开按键；柱子上方一块小牌子：型号名、类别、名额 / 冷却（G.S.vehAvail）
--   有挂点的飞机：服务器发 { op = "hangar" } → 弹出 3D 挂载界面（右下按钮是「生成」），选好发 padSpawn；每种飞机记住上次选的挂载
--   飞机、直升机的召唤位（Depots.lua 的 summon）：牌子写「召唤飞机 / 直升机」；按 E 服务器发 { op = "airPick" } → 弹出机型列表（卡片：名字、用途、
--     舰载 / 隐身 / 航炮 / 挂点数 / 内油），点一架 → 有挂点的进挂载编辑器（可以挂副油箱），选好发 padSpawn(召唤位, 挂载, 机型)
--   地面载具的召唤位（用户：召唤点里自己选哪种车，不要固定）：牌子写「召唤地面载具」；按 E 服务器发 { op = "vehPick" } → 弹出本队全部车型
--     （按坦克 / 装甲车 / 防空 / 火炮分组，每张卡片：名字、类别和名额 / 冷却、履带 / 轮式、主炮、两栖），点一辆 → padSpawn(召唤位, nil, 型号)
--   图标（用户 11-23：「召唤坦克和飞机、舰船的界面，选择的界面名字下面要带图标」）：卡片的名字下面、一型一位的码位（舰艇码头）牌子的名字下面
--     放这一型的侧影（HudIcons：原模型正侧面拍的 veh_ / air_ / ship_<型号>，HudArt 解成 EditableImage；游戏设置里没开 Mesh / Image API 时不画）
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
  -- 这一型的侧影图标名（HudIcons）
  local function iconName(id)
    if VD.get(id) then return "veh_" .. id end
    if AD.get(id) then return "air_" .. id end
    if SD.get(id) then return "ship_" .. id end
    return nil
  end
  -- 名字下面的侧影：灰度图按 col 染色、等比缩进框里；用不了 EditableImage 时是空的（不挡字）
  local function iconAt(parent, id, size, pos, col)
    local im = Instance.new("ImageLabel")
    im.Name = "Icon"
    im.BackgroundTransparency = 1
    im.Size, im.Position = size, pos
    im.ScaleType = Enum.ScaleType.Fit
    im.ImageColor3 = col or RGB(226, 232, 238)
    im.Parent = parent
    local n = id and iconName(id)
    if n and G.hudIconOn then G.hudIconOn(im, n) end
    return im
  end

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
    bar.BackgroundColor3 = (team == "atk") and RGB(232, 84, 72) or RGB(76, 200, 104)
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
    local icon = iconAt(f, nil, UDim2.new(1, -24, 0, 44), UDim2.fromOffset(12, 28), RGB(220, 228, 234))   -- 名字下面的侧影（refresh 里按型号装上）
    icon.Visible = false
    return bb, name, info, bar, icon
  end

  local function add(m)
    if pads[m] then return end
    local post = m:FindFirstChild("Post")
    local prompt = post and post:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then return end
    local bb, name, info, bar, icon = sign(post, m:GetAttribute("Team"))
    pads[m] = { prompt = prompt, bb = bb, name = name, info = info, bar = bar, icon = icon }
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
        local ground = summon and m:GetAttribute("Kind") == "veh"   -- 地面召唤位：哪一型都能选，名额按类别
        local title = ground and T("pad.summonVeh") or summon and T(m:GetAttribute("Heli") and "pad.summonHeli" or "pad.summonJet") or T("veh." .. id)
        x.prompt.Enabled = mine
        x.prompt.ActionText = T(ground and "pad.summonVehAct" or summon and "pad.summon" or "pad.spawn")
        x.prompt.ObjectText = title
        x.bb.Enabled = mine
        x.name.Text = title
        -- 一型一位（舰艇码头、老的单型车位）：名字下面放这一型的侧影，牌子加高、类别那行挪到图下面；召唤位（能选好几型）不放
        local iconId = (not summon) and id or nil
        if x.iconId ~= iconId then
          x.iconId = iconId
          local n = iconId and iconName(iconId)
          local ok = n and G.hudIconOn and G.hudIconOn(x.icon, n)
          x.icon.Visible = ok == true
          x.bb.Size = UDim2.fromOffset(210, ok and 96 or 50)
          x.info.Position = UDim2.fromOffset(12, ok and 74 or 28)
        end
        if ground then
          x.info.Text = open and T("pad.vehKinds") or T("pad.need" .. need)
          x.info.TextColor3 = open and RGB(150, 156, 162) or RGB(214, 120, 96)
        else
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
  local ROLE = { j20 = "fighter", j35 = "fighter", j15t = "fighter", f22 = "fighter", f35 = "fighter", j16 = "strike", j11 = "fighter", j10 = "fighter", j36 = "fighter", a10c = "attack",
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
  panel.Size = UDim2.fromOffset(820, 540)   -- 卡片带了图标、高一些：面板也高一点，放不下的往下滚
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
  local grid = Instance.new("ScrollingFrame")   -- 守方地面载具 15 型、攻方喷气机 10 型：一屏放不下的往下滚
  grid.Size, grid.Position = UDim2.new(1, -40, 1, -140), UDim2.fromOffset(24, 80)
  grid.BackgroundTransparency, grid.BorderSizePixel = 1, 0
  grid.ScrollingDirection = Enum.ScrollingDirection.Y
  grid.ScrollBarThickness = 5
  grid.ScrollBarImageColor3 = RGB(200, 206, 212)
  grid.CanvasSize = UDim2.new()
  grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
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

  local function quota(cat)   -- 这一类现在的名额、冷却：能不能再召唤、给卡片写的字
    local S = G.S
    local av = S and S.vehAvail and S.vehAvail[cat]
    if not av then return true, "" end
    if av.u >= av.cap then return false, (av.cd and av.cd > 0) and T("pad.cd", av.cd) or T("pad.full", av.u, av.cap) end
    return true, T("pad.ready", av.u, av.cap)
  end

  -- R 币解锁的机型（B-2 199 R 币）：没买的卡片上写价钱，点了弹出 Roblox 的购买框
  local function lockedPass(id)
    local pass = G.passFor and G.passFor(id)
    if pass and G.passOk and not G.passOk(pass) then return pass end
    return nil
  end
  local TMods = require(RS:WaitForChild("TankMods"))
  local lastMods = {}   -- 每型坦克上次选的改装
  local function choose(id)
    local pad = pickPad
    local lp = lockedPass(id)
    if lp then
      if G.buyPass then G.buyPass(lp) end
      return
    end
    local vd = VD.get(id)
    if vd then   -- 地面载具：这一类名额满了就不关列表，提示一下
      local ok, why = quota(vd.cat)
      if not ok then
        if G.toast then G.toast(T("vcat." .. vd.cat) .. "  " .. why, "bad") end
        return
      end
      closePick()
      -- 有改装的坦克（TankMods）：先进改装界面（Garage.lua，像飞机选挂载那样），选好了「出车」才生成；挂载那一格放改装
      if pad and G.openGarage and TMods.has(id) then
        G.openGarage(id, lastMods[id], function(mods)
          lastMods[id] = mods
          G.R.Act:FireServer("padSpawn", pad, mods, id)
        end)
        return
      end
      if pad then G.R.Act:FireServer("padSpawn", pad, false, id) end   -- 挂载那一格传 false：中间夹着 nil 的参数表有空洞
      return
    end
    closePick()
    local d = AD.get(id)
    if not d or not pad then return end
    if d.st and #d.st > 0 and G.openHangar then
      G.openHangar(id, lastLoad[id], function(load, _, fuel)
        lastLoad[id], lastFuel[id] = load, fuel
        G.R.Act:FireServer("padSpawn", pad, load, id, fuel)
      end, nil, { confirm = "pad.spawn", fuel = lastFuel[id] })
    else
      G.R.Act:FireServer("padSpawn", pad, false, id)
    end
  end

  -- 地面载具的卡片（比飞机的小一号：一个召唤位能选十几型）
  local CAT_ORDER = { tank = 1, apc = 2, aa = 3, arty = 4 }
  local function vehCards(ids)
    gl.CellSize, gl.CellPadding = UDim2.fromOffset(182, 116), UDim2.fromOffset(8, 8)
    pTitle.Text = T("pad.summonVeh")
    pSub.Text = T("pick.subVeh")
    local list = {}
    for i, id in ipairs(ids) do
      local d = VD.get(id)
      if d then table.insert(list, { id = id, d = d, o = (CAT_ORDER[d.cat] or 9) * 100 + i }) end
    end
    table.sort(list, function(a, b) return a.o < b.o end)
    for i, it in ipairs(list) do
      local d, id = it.d, it.id
      local ok, why = quota(d.cat)
      local b = Instance.new("TextButton")
      b.Name = "Pick_" .. id
      b.Text = ""
      b.LayoutOrder = i
      b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = RGB(24, 27, 31), ok and 0.05 or 0.45, 0
      b.AutoButtonColor = ok
      b.Parent = grid
      local stroke = Instance.new("UIStroke")
      stroke.Color, stroke.Transparency, stroke.Thickness = RGB(255, 255, 255), 0.9, 1
      stroke.Parent = b
      b.MouseEnter:Connect(function() stroke.Transparency = ok and 0.4 or 0.8 end)
      b.MouseLeave:Connect(function() stroke.Transparency = 0.9 end)
      label(b, T("veh." .. id), UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 7), 15, ok and RGB(240, 242, 244) or RGB(130, 134, 138), Enum.Font.GothamBlack)
      iconAt(b, id, UDim2.new(1, -20, 0, 42), UDim2.fromOffset(10, 29), ok and RGB(226, 232, 238) or RGB(110, 114, 118))   -- 名字下面的侧影
      local cl = label(b, T("vcat." .. d.cat) .. "   " .. why, UDim2.new(1, -20, 0, 14), UDim2.fromOffset(10, 74), 11, ok and RGB(214, 190, 120) or RGB(214, 120, 96), Enum.Font.GothamBold)
      cl.Name = "Quota"
      local tags = { T((d.arch == "wheeled") and "pick.wheeled" or "pick.tracked") }
      if d.weapons and d.weapons[1] then table.insert(tags, T("vw." .. d.weapons[1])) end
      if d.amphib then table.insert(tags, T("pick.amphib")) end
      label(b, table.concat(tags, " · "), UDim2.new(1, -20, 0, 14), UDim2.fromOffset(10, 93), 11, RGB(170, 176, 182), Enum.Font.GothamMedium)
      b.Activated:Connect(function() choose(id) end)
      table.insert(cards, b)
    end
  end

  local function openPick(padId, ids, heli, ground)
    for _, c in ipairs(cards) do c:Destroy() end
    cards = {}
    pickPad = padId
    grid.CanvasPosition = Vector2.zero
    cancel.Text = T("pick.cancel")
    if ground then
      vehCards(ids)
      pick.Enabled = true
      return
    end
    gl.CellSize, gl.CellPadding = UDim2.fromOffset(250, 152), UDim2.fromOffset(10, 10)
    pTitle.Text = T(heli and "pad.summonHeli" or "pad.summonJet")
    local S = G.S
    local av = S and S.vehAvail and S.vehAvail[heli and "heli" or "jet"]
    local st = ""
    if av then st = (av.u >= av.cap) and ((av.cd and av.cd > 0) and T("pad.cd", av.cd) or T("pad.full", av.u, av.cap)) or T("pad.ready", av.u, av.cap) end
    pSub.Text = T("pick.sub") .. "   ·   " .. st
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
        local ic = iconAt(b, id, UDim2.new(1, -24, 0, 50), UDim2.fromOffset(12, 36))   -- 名字下面的侧影
        label(b, T("arole." .. (ROLE[id] or (d.kind == "heli" and "uheli" or "fighter"))), UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 88), 12, RGB(214, 190, 120), Enum.Font.GothamBold)
        local lp = lockedPass(id)
        if lp then   -- 右上角：解锁 R$ 价钱（琥珀色），卡片暗一点
          local pt = label(b, T("pass.lockTag", G.Config.Passes[lp].price), UDim2.fromOffset(120, 18), UDim2.new(1, -132, 0, 12), 12, RGB(255, 196, 92), Enum.Font.GothamBlack,
            Enum.TextXAlignment.Right)
          pt.Name = "PassTag"
          b.BackgroundTransparency = 0.3
          stroke.Color, stroke.Transparency = RGB(255, 196, 92), 0.55
          ic.ImageColor3 = RGB(150, 140, 118)   -- 没解锁的：侧影暗一点、偏琥珀
        end
        local tags = {}
        if d.carrier then table.insert(tags, T("pick.carrier")) end
        if d.stealth then table.insert(tags, T("pick.stealth")) end
        if d.gun then table.insert(tags, T("pick.gun")) end
        if d.st and #d.st > 0 then table.insert(tags, T("pick.st", #d.st)) end
        if AD.fuelMin then table.insert(tags, T("pick.fuel", AD.fuelMin(d))) end
        local tl = label(b, table.concat(tags, " · "), UDim2.new(1, -24, 0, 32), UDim2.fromOffset(12, 108), 12, RGB(170, 176, 182), Enum.Font.GothamMedium)
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
    if d.op == "vehPick" and type(d.ids) == "table" then
      openPick(d.pad, d.ids, false, true)
      return
    end
    if d.op ~= "hangar" or not G.openHangar then return end
    local id, pad = d.id, d.pad
    if not AD.get(id) then return end
    G.openHangar(id, lastLoad[id], function(load, _, fuel)
      lastLoad[id], lastFuel[id] = load, fuel
      G.R.Act:FireServer("padSpawn", pad, load, false, fuel)
    end, nil, { confirm = "pad.spawn", fuel = lastFuel[id] })
  end)
end

return Depot
