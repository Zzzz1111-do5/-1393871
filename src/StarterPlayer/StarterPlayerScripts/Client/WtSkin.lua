-- Roblox全面大战场（客户端）——机库里选涂装、贴花（用户 11-25「全部都做」⑯）
--   出击阵容卡片上的「涂装」（TechUI.lua 调 G.openSkin(科技树的键)）：六种涂装（色块）、战术号码（三位数，留空就不贴）、国徽开关；
--   选了就发服务器（WtMatch.lua G.ACT.wtSkinSet），这一局里出这辆车按它；画法在 View.lua（零件拼的车直接上色，原模型乘色调）
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local WtSkin = {}

function WtSkin.init(G)
  local SK = require(RS:WaitForChild("WtSkins"))
  local TT = require(RS:WaitForChild("TechTree"))
  local me = Players.LocalPlayer
  local RGB, UD2, V2 = Color3.fromRGB, UDim2.new, Vector2.new
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local BOLD, MED = Enum.Font.BuilderSansMedium, Enum.Font.BuilderSans
  local WHITE, DIM, GOLD = RGB(236, 240, 242), RGB(150, 158, 164), RGB(255, 210, 120)
  local zh = true   -- 多语言（11-28）：中文（简 / 繁）
  if G.isZh then zh = G.isZh() end

  local gui = Instance.new("ScreenGui")
  gui.Name = "WtSkin"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 14
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")

  local saved = {}   -- 键 → { c, n, e }
  local panel = nil
  local function close()
    if panel then panel:Destroy() panel = nil end
    gui.Enabled = false
  end
  local function label(parent, s, size, pos, ts, col, font)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size, l.Position = size, pos
    l.Text, l.TextSize, l.TextColor3, l.Font = s, ts or 14, col or WHITE, font or BOLD
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
  end
  function G.openSkin(key)
    close()
    local it = TT.get and TT.get(key)
    local cur = saved[key] or { c = "std", n = nil, e = true }
    gui.Enabled = true
    panel = Instance.new("Frame")
    panel.Name = "SkinPanel"
    panel.Size, panel.Position, panel.AnchorPoint = UDim2.fromOffset(460, 250), UD2(0.5, 0, 0.5, 0), V2(0.5, 0.5)
    panel.BackgroundColor3, panel.BackgroundTransparency, panel.BorderSizePixel = RGB(12, 14, 17), 0.05, 0
    panel.Parent = gui
    local st = Instance.new("UIStroke")
    st.Color, st.Transparency = RGB(110, 120, 126), 0.35
    st.Parent = panel
    local nm = it and T("tree." .. key) or key
    label(panel, nm .. "  ·  " .. T("wsk.title"), UD2(1, -24, 0, 24), UD2(0, 12, 0, 10), 16)
    -- 涂装：一排色块
    local sw = {}
    local function redraw()
      for k, b in pairs(sw) do
        local s2 = b:FindFirstChildOfClass("UIStroke")
        if s2 then s2.Thickness, s2.Color = (cur.c == k) and 3 or 1, (cur.c == k) and GOLD or RGB(90, 96, 100) end
      end
    end
    local function send()
      saved[key] = { c = cur.c, n = cur.n, e = cur.e }
      G.R.Act:FireServer("wtSkinSet", key, cur.c, cur.n, cur.e)
      redraw()
    end
    for i, k in ipairs(SK.ORDER) do
      local C = SK.CAMO[k]
      local b = Instance.new("TextButton")
      b.Name = "Camo_" .. k
      b.Size, b.Position = UDim2.fromOffset(68, 62), UD2(0, 12 + (i - 1) * 73, 0, 44)
      b.BackgroundColor3, b.BorderSizePixel = C.base or RGB(60, 64, 60), 0
      b.Text = ""
      b.Parent = panel
      local s2 = Instance.new("UIStroke")
      s2.Parent = b
      if C.dark then   -- 迷彩的另两种颜色两小块
        for j, col in ipairs({ C.dark, C.light }) do
          local f = Instance.new("Frame")
          f.Size, f.Position = UD2(0.36, 0, 0.3, 0), UD2(0.08 + (j - 1) * 0.46, 0, 0.1, 0)
          f.BackgroundColor3, f.BorderSizePixel = col, 0
          f.Parent = b
        end
      end
      local l = label(b, G.L(C.zh, C.en), UD2(1, 0, 0, 16), UD2(0, 0, 1, -18), 11, WHITE, MED)
      l.TextXAlignment = Enum.TextXAlignment.Center
      l.TextStrokeTransparency = 0.3
      b.MouseButton1Click:Connect(function() cur.c = k send() end)
      sw[k] = b
    end
    -- 战术号码
    label(panel, T("wsk.no"), UD2(0, 120, 0, 24), UD2(0, 12, 0, 122), 14)
    local tb = Instance.new("TextBox")
    tb.Name = "TacNo"
    tb.Size, tb.Position = UDim2.fromOffset(90, 28), UD2(0, 130, 0, 120)
    tb.BackgroundColor3, tb.BorderSizePixel = RGB(28, 32, 36), 0
    tb.Text, tb.PlaceholderText = cur.n and string.format("%03d", cur.n) or "", "213"
    tb.TextSize, tb.Font, tb.TextColor3 = 16, BOLD, WHITE
    tb.ClearTextOnFocus = false
    tb.Parent = panel
    tb.FocusLost:Connect(function()
      local n = tonumber(string.match(tb.Text or "", "%d+") or "")
      cur.n = n and math.clamp(n, 0, 999) or nil
      tb.Text = cur.n and string.format("%03d", cur.n) or ""
      send()
    end)
    -- 国徽
    local eb = Instance.new("TextButton")
    eb.Name = "Emblem"
    eb.Size, eb.Position = UDim2.fromOffset(160, 28), UD2(0, 240, 0, 120)
    eb.BackgroundColor3, eb.BorderSizePixel = RGB(40, 52, 46), 0
    eb.TextSize, eb.Font, eb.TextColor3 = 14, BOLD, WHITE
    eb.Parent = panel
    local function ebTxt() eb.Text = T(cur.e and "wsk.embOn" or "wsk.embOff") end
    ebTxt()
    eb.MouseButton1Click:Connect(function() cur.e = not cur.e ebTxt() send() end)
    label(panel, T("wsk.note"), UD2(1, -24, 0, 34), UD2(0, 12, 0, 160), 11, DIM, MED).TextWrapped = true
    local ok = Instance.new("TextButton")
    ok.Name = "Close"
    ok.Size, ok.Position = UDim2.fromOffset(100, 32), UD2(1, -112, 1, -44)
    ok.BackgroundColor3, ok.BorderSizePixel = RGB(52, 70, 58), 0
    ok.Text, ok.TextSize, ok.Font, ok.TextColor3 = T("wta2.close"), 14, BOLD, WHITE
    ok.Parent = panel
    ok.MouseButton1Click:Connect(close)
    redraw()
    if not saved[key] then send() end
  end
  G.closeSkin = close
  G.frameConn("WtSkin", function()
    if panel and G.S and G.S.alive then close() end
  end)
end

return WtSkin
