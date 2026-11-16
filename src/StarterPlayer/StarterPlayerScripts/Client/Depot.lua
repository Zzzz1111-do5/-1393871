-- Roblox全面大战场——地图里的载具生成点（客户端）：Depots.lua 摆的终端柱
--   按语言写按键文字（「生成」+ 型号名），只给自己队的生成点开按键；柱子上方一块小牌子：型号名、类别、名额 / 冷却（G.S.vehAvail）
--   有挂点的飞机：服务器发 { op = "hangar" } → 弹出 3D 挂载界面（右下按钮是「生成」），选好发 padSpawn；每种飞机记住上次选的挂载
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
        x.prompt.Enabled = mine
        x.prompt.ActionText = T("pad.spawn")
        x.prompt.ObjectText = T("veh." .. id)
        x.bb.Enabled = mine
        x.name.Text = T("veh." .. id)
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

  -- 有挂点的飞机：服务器让开挂载界面
  G.R.Drive.OnClientEvent:Connect(function(d)
    if type(d) ~= "table" or d.op ~= "hangar" or not G.openHangar then return end
    local id, pad = d.id, d.pad
    if not AD.get(id) then return end
    G.openHangar(id, lastLoad[id], function(load)
      lastLoad[id] = load
      G.R.Act:FireServer("padSpawn", pad, load)
    end, nil, { confirm = "pad.spawn" })
  end)
end

return Depot
