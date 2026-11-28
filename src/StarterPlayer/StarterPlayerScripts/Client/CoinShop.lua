-- 全面大战场（客户端）——金币充值（R 币买金币；用户 11-28「你做个金币充值界面好了收robux」，服务器 Shop.lua）
--   一个窗口：标题「金币充值」、现有多少金币；一排五档（Config.CoinPacks）：一摞金币、到账多少、「赠送 +N」、价钱（R$，优先显示 Roblox 查到的真价钱）、
--   「购买」——点了服务器弹 Roblox 的购买框（buyCoins），付完钱 Roblox 调服务器的 ProcessReceipt，金币到账、弹「已到账」
--   还没在创作者后台上架的那一档（Config id = 0）：写「未上架」、点不了
--   打开：G.openCoinShop()——机库右上金币旁边的「+」、科技树里「金币不够」那个键；Esc / ✕ 关
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local CoinShop = {}

function CoinShop.init(G)
  local TH = require(RS:WaitForChild("Theme"))
  local Config = require(RS:WaitForChild("Config"))
  local okM, MPS = pcall(function() return game:GetService("MarketplaceService") end)
  if not okM then MPS = nil end
  local me = Players.LocalPlayer
  local RGB, U2, V2 = Color3.fromRGB, UDim2, Vector2.new
  local function L(zh, en) return G.L(zh, en) end   -- 多语言（11-28）
  local TEXT, MUTE, FAINT, GOOD, AMBER = TH.C.TEXT, TH.C.MUTE, TH.C.FAINT, TH.C.GOOD, TH.C.WARN
  local GOLD, GOLD_D = RGB(236, 184, 64), RGB(150, 104, 22)
  local packs = Config.CoinPacks or {}

  local function fmt(n)
    local s = tostring(math.floor(n or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then out = out:sub(2) end
    return out
  end

  local gui = Instance.new("ScreenGui")
  gui.Name = "CoinShop"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 24   -- 机库（12）、出击页（13）、挂载表（22）上面，设置（30）下面
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  G.coinShopGui = gui   -- 测试用

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
    t.TextXAlignment = xa or Enum.TextXAlignment.Center
    if name then t.Name = name end
    t.Parent = parent
    return t
  end
  local function corner(o, r) local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r or 3) c.Parent = o return c end
  local function stroke(o, col, tr, th) local s = Instance.new("UIStroke") s.Color, s.Transparency, s.Thickness = col, tr or 0, th or 1 s.Parent = o return s end

  local dim = frame(gui, U2.fromScale(1, 1), nil, RGB(4, 6, 8), 0.35, "Dim")
  dim.Active = true
  local W, H = 980, 430
  local box = frame(gui, U2.fromOffset(W, H), U2.fromScale(0.5, 0.5), RGB(0, 0, 0), 1, "Box")
  box.AnchorPoint = V2(0.5, 0.5)
  local fit = Instance.new("UIScale")
  fit.Parent = box
  local win = frame(box, U2.fromScale(1, 1), U2.fromScale(0.5, 0.5), RGB(18, 22, 26), 0.02, "Win")
  win.AnchorPoint = V2(0.5, 0.5)
  corner(win, 3)
  stroke(win, TH.C.LINE or RGB(80, 86, 92), 0.6)
  text(win, L("金币充值", "Buy coins"), U2.new(1, -80, 0, 34), U2.fromOffset(18, 8), TH.S.title, TEXT, TH.F.title, Enum.TextXAlignment.Left, "Title")
  local bal = text(win, "", U2.fromOffset(360, 22), U2.new(1, -420, 0, 14), TH.S.body, GOLD, TH.F.mono or TH.F.bold, Enum.TextXAlignment.Right, "Balance")
  local close = Instance.new("TextButton")
  close.Name = "Close"
  close.Text, close.Font, close.TextSize, close.TextColor3 = "✕", TH.F.bold, TH.S.body, TEXT
  close.Size, close.Position = U2.fromOffset(34, 30), U2.new(1, -44, 0, 10)
  close.BackgroundColor3, close.BackgroundTransparency, close.BorderSizePixel, close.AutoButtonColor = TH.C.RAISE or RGB(40, 46, 52), 0.1, 0, false
  corner(close, 2)
  close.Parent = win
  frame(win, U2.new(1, -20, 0, 1), U2.fromOffset(10, 48), TH.C.LINE or RGB(80, 86, 92), 0.85)
  local note = text(win, L("用 Roblox 的 R 币支付。付款成功后金币马上到账，可以买科技树里研究好的载具。",
    "Paid with Robux. Coins arrive right after the purchase and can buy researched vehicles in the tech tree."),
    U2.new(1, -36, 0, 36), U2.new(0, 18, 1, -46), TH.S.small, FAINT, TH.F.body, Enum.TextXAlignment.Left, "Note")
  note.TextWrapped = true

  -- 一摞金币（几片扁圆叠起来，越贵的档叠得越高）
  local function stack(parent, n, cx, by)
    for i = 1, n do
      local c = frame(parent, U2.fromOffset(58, 16), U2.fromOffset(cx - 29 + ((i % 2 == 0) and 3 or -2), by - i * 7), GOLD, 0, "Disc")
      corner(c, 8)
      stroke(c, GOLD_D, 0, 1.5)
      local hi = frame(c, U2.new(1, -16, 0, 3), U2.fromOffset(8, 3), RGB(255, 226, 140), 0.2)
      corner(hi, 2)
    end
  end

  local cards = {}
  local prices = {}   -- [产品编号] = Roblox 查到的价钱
  local function priceText(p)
    local r = (p.id or 0) ~= 0 and prices[p.id] or nil
    return "R$ " .. fmt(r or p.robux or 0)
  end
  local function act(...)
    local args = table.pack(...)
    pcall(function() G.R.Act:FireServer(table.unpack(args, 1, args.n)) end)
  end

  local CW, GAP = 176, 13
  local x0 = (W - (#packs * CW + (#packs - 1) * GAP)) / 2
  for i, p in ipairs(packs) do
    local c = frame(win, U2.fromOffset(CW, 300), U2.fromOffset(x0 + (i - 1) * (CW + GAP), 62), RGB(28, 33, 39), 0.05, "Pack_" .. p.key)
    corner(c, 3)
    local st = stroke(c, RGB(90, 96, 104), 0.5)
    -- 顶上：赠送多少
    if (p.bonus or 0) > 0 then
      local rib = frame(c, U2.new(1, -16, 0, 22), U2.fromOffset(8, 8), RGB(52, 98, 58), 0.1, "Bonus")
      corner(rib, 2)
      text(rib, L("赠送 +", "Bonus +") .. fmt(p.bonus), U2.fromScale(1, 1), nil, TH.S.small, RGB(206, 246, 196), TH.F.bold)
    end
    stack(c, 2 + i, CW / 2, 150)
    text(c, fmt(p.coins), U2.new(1, 0, 0, 34), U2.fromOffset(0, 160), TH.S.title + 4, GOLD, TH.F.title, nil, "Amount")
    text(c, L("金币", "coins"), U2.new(1, 0, 0, 18), U2.fromOffset(0, 194), TH.S.small, MUTE, TH.F.body)
    local function listed() return (p.id or 0) ~= 0 end   -- 现查（改了 Config 的编号马上算数）
    local b = Instance.new("TextButton")
    b.Name = "Buy"
    b.AutoButtonColor = false
    b.Size, b.Position = U2.new(1, -24, 0, 40), U2.new(0, 12, 1, -56)
    b.Font, b.TextSize = TH.F.title, TH.S.body
    b.BorderSizePixel = 0
    b.Parent = c
    corner(b, 2)
    local function paint()
      if listed() then
        b.Text, b.TextColor3 = priceText(p), RGB(24, 18, 8)
        b.BackgroundColor3, b.BackgroundTransparency = AMBER, 0
      else
        b.Text, b.TextColor3 = L("未上架", "Not on sale"), FAINT
        b.BackgroundColor3, b.BackgroundTransparency = RGB(44, 48, 54), 0.2
      end
    end
    paint()
    b.MouseEnter:Connect(function() if listed() then st.Transparency, st.Color = 0, AMBER end end)
    b.MouseLeave:Connect(function() st.Transparency, st.Color = 0.5, RGB(90, 96, 104) end)
    b.MouseButton1Click:Connect(function()
      if not listed() then
        if G.toast then G.toast(L("这一档还没上架（创作者后台建好开发者产品、把编号填进 Config.CoinPacks）", "This pack isn't on sale yet"), "info") end
        return
      end
      act("buyCoins", p.key)
    end)
    cards[#cards + 1] = { p = p, paint = paint }
  end

  local function refresh()
    local c = me:GetAttribute("Coins")
    bal.Text = L("现有 ", "Balance ") .. ((type(c) == "number") and fmt(c) or "—") .. L(" 金币", " coins")
    for _, cd in ipairs(cards) do cd.paint() end
  end
  me:GetAttributeChangedSignal("Coins"):Connect(function() if gui.Enabled then refresh() end end)

  -- 真价钱：开着的时候问一次 Roblox（后台改了价钱这里跟着变；问不到就用 Config 的数）
  local asked = false
  local function askPrices()
    if asked or not MPS then return end
    asked = true
    for _, p in ipairs(packs) do
      if (p.id or 0) ~= 0 then
        task.spawn(function()
          local ok, info = pcall(function() return MPS:GetProductInfo(p.id, Enum.InfoType.Product) end)
          if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
            prices[p.id] = info.PriceInRobux
            if gui.Enabled then refresh() end
          end
        end)
      end
    end
  end

  local function fitScale()
    local vs = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or V2(1280, 720)
    fit.Scale = math.clamp(math.min((vs.X - 40) / W, (vs.Y - 40) / H), 0.45, 1.4)
  end
  function G.openCoinShop()
    fitScale()
    refresh()
    gui.Enabled = true
    askPrices()
    if G.uiPop and not (G.reducedMotion and G.reducedMotion()) then G.uiPop(win, 0.97, true) end
    if G.sfx then pcall(G.sfx, "uiClick") end
    return true
  end
  function G.closeCoinShop() gui.Enabled = false end
  G.coinShopOpen = function() return gui.Enabled end
  close.MouseButton1Click:Connect(G.closeCoinShop)
  UIS.InputBegan:Connect(function(io)
    if gui.Enabled and io.KeyCode == Enum.KeyCode.Escape then G.closeCoinShop() end
  end)
  local cam = workspace.CurrentCamera
  if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() if gui.Enabled then fitScale() end end) end
  -- 付完款：服务器发「已到账」（G.msg good shop.thanks）——窗口开着就把余额刷一下（Coins 属性会变，上面已经接着）
end

return CoinShop
