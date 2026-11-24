-- 全面大战场（客户端）——金币（服务器 Economy.lua；用户 11-23：载具、配件拿金币解锁，金币打 PvP、PvE 挣）
--   左上角一个小牌子「◉ 1,250 金币」：开着菜单（主菜单、部署界面、召唤点的机型列表、改枪……）时一直显示；打仗时金币变了亮几秒，
--   旁边弹一下「+350」/「-1500」
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Coins = {}

function Coins.init(G)
  local T = G.T or function(k) return k end
  local player = Players.LocalPlayer
  local RGB = Color3.fromRGB
  local GOLD = RGB(255, 206, 96)

  local gui = Instance.new("ScreenGui")
  gui.Name = "Coins"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 45
  gui.Parent = player:WaitForChild("PlayerGui")
  local badge = Instance.new("Frame")
  badge.Name = "Badge"
  badge.Position = UDim2.fromOffset(16, 10)
  badge.Size = UDim2.fromOffset(150, 28)
  badge.BackgroundColor3 = RGB(8, 9, 11)
  badge.BackgroundTransparency = 0.3
  badge.BorderSizePixel = 0
  badge.Visible = false
  badge.Parent = gui
  local st = Instance.new("UIStroke")
  st.Color, st.Transparency, st.Thickness = GOLD, 0.6, 1
  st.Parent = badge
  local txt = Instance.new("TextLabel")
  txt.Name = "Amount"
  txt.BackgroundTransparency = 1
  txt.Position = UDim2.fromOffset(10, 0)
  txt.Size = UDim2.new(1, -16, 1, 0)
  txt.Font = Enum.Font.GothamBold
  txt.TextSize = 14
  txt.TextColor3 = GOLD
  txt.TextXAlignment = Enum.TextXAlignment.Left
  txt.Parent = badge
  local pop = Instance.new("TextLabel")
  pop.Name = "Delta"
  pop.BackgroundTransparency = 1
  pop.Position = UDim2.fromOffset(170, 4)
  pop.Size = UDim2.fromOffset(120, 20)
  pop.Font = Enum.Font.GothamBlack
  pop.TextSize = 16
  pop.TextXAlignment = Enum.TextXAlignment.Left
  pop.TextTransparency = 1
  pop.TextStrokeTransparency = 1
  pop.Parent = gui

  -- PvE 关卡（Pve.lua）：左上角一行「PvE 第 3 关 · 夜袭机场 · 拿下 3 个据点」
  local pveTag = Instance.new("TextLabel")
  pveTag.Name = "PveTag"
  pveTag.BackgroundTransparency = 1
  pveTag.Position = UDim2.fromOffset(18, 42)
  pveTag.Size = UDim2.fromOffset(420, 18)
  pveTag.Font = Enum.Font.GothamBold
  pveTag.TextSize = 13
  pveTag.TextColor3 = RGB(236, 240, 236)
  pveTag.TextStrokeTransparency = 0.5
  pveTag.TextXAlignment = Enum.TextXAlignment.Left
  pveTag.Visible = false
  pveTag.Parent = gui

  local function fmt(n)
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then out = out:sub(2) end
    return out
  end
  local shownUntil = 0
  local last = nil
  local function refresh()
    local c = player:GetAttribute("Coins")
    if type(c) ~= "number" then return end
    if player:GetAttribute("CoinsInf") == true then   -- 无限金币（Config.Economy.infinite）：写 ∞，不弹加减
      txt.Text = "◉ " .. T("eco.coins", "∞")
      last = c
      return
    end
    txt.Text = "◉ " .. T("eco.coins", fmt(c))
    if last ~= nil and c ~= last then
      local d = c - last
      pop.Text = (d > 0 and "+" or "-") .. fmt(math.abs(d))
      pop.TextColor3 = (d > 0) and GOLD or RGB(230, 120, 100)
      pop.TextTransparency, pop.TextStrokeTransparency = 0, 0.5
      pop.Position = UDim2.fromOffset(170, 4)
      pcall(function()
        TweenService:Create(pop, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
          { TextTransparency = 1, TextStrokeTransparency = 1, Position = UDim2.fromOffset(170, -14) }):Play()
      end)
      shownUntil = os.clock() + 5
    end
    last = c
  end
  player:GetAttributeChangedSignal("Coins"):Connect(refresh)
  player:GetAttributeChangedSignal("CoinsInf"):Connect(refresh)
  refresh()
  G.coinsShown = function() return badge.Visible end   -- 测试用

  local acc = 0
  G.frameConn("Coins", function(dt)
    acc += dt
    if acc < 0.15 then return end
    acc = 0
    local has = type(player:GetAttribute("Coins")) == "number"
    local menu = (G.menuShown and G.menuShown()) or (G.menuOpen and G.menuOpen()) or false
    badge.Visible = has and (menu or os.clock() < shownUntil)
    local n = G.S and G.S.pve
    local L = n and G.Config.Pve and G.Config.Pve.levels[n]
    pveTag.Visible = L ~= nil and not (G.menuShown and G.menuShown())
    if L then
      local goal = L.caps and T("pve.goalCaps", L.caps) or T("pve.goalTickets", L.tickets or 0)
      pveTag.Text = T("pve.hud", n, T("pve.n" .. n), goal)
      pveTag.Position = UDim2.fromOffset(18, badge.Visible and 42 or 12)
    end
  end)
end

return Coins
