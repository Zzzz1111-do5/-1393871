-- Roblox全面大战场（客户端）——机库里配弹（用户 11-25「全部都做」④：战雷出车前选每种弹带几发）
--   机库出击阵容卡片上的「弹药」（TechUI.lua 调 G.openAmmo(科技树的键, 能打前几种)）：主炮每种弹一行（名字、0 米穿深、− / +，
--   按住 Shift 一次 5 发），底下总数 / 满载、待发弹架几发；「默认」「带一半」「满载」；改了就发服务器（Wt.lua G.ACT.wtAmmoSet），
--   这一局里再出这辆车照这个配。少带弹：打中弹架不容易殉爆（弹架空了根本不炸），但打几发就得回据点补
--   没研究的弹种（科技树改装「第二种弹」「第三种弹」）灰着、配不了
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local WtAmmo = {}

function WtAmmo.init(G)
  local VD = require(RS:WaitForChild("VehDefs"))
  local BAL = require(RS:WaitForChild("Ballistics"))
  local TT = require(RS:WaitForChild("TechTree"))
  local WD = require(RS:WaitForChild("WtDamage"))
  local me = Players.LocalPlayer
  local RGB, UD2, V2 = Color3.fromRGB, UDim2.new, Vector2.new
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local BOLD, MED = Enum.Font.BuilderSansMedium, Enum.Font.BuilderSans
  local TH = G.Theme   -- 统一外观（docs/style.md）
  local WHITE, DIM, GOLD, BAD = TH.C.TEXT, TH.C.MUTE, TH.C.WARN, TH.C.BAD
  local SPLIT = { 5, 3, 2, 1, 1 }   -- 默认配弹（同服务器 Wt.lua）

  local gui = Instance.new("ScreenGui")
  gui.Name = "WtAmmo"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 14   -- 盖在机库（TechUI 12）上面
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")

  local function frame(parent, size, pos, col, tr, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position, f.AnchorPoint = size, pos or UD2(), anchor or V2()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = col or RGB(10, 12, 14), tr or 0, 0
    f.Parent = parent
    return f
  end
  local function text(parent, s, size, pos, ts, col, font, align)
    local l = Instance.new("TextLabel")
    l.Size, l.Position = size, pos or UD2()
    l.BackgroundTransparency = 1
    l.Text, l.TextSize, l.TextColor3, l.Font = s or "", ts or 14, col or WHITE, font or BOLD
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.Parent = parent
    return l
  end
  local function button(parent, s, size, pos, on)
    local b = Instance.new("TextButton")
    b.Size, b.Position = size, pos or UD2()
    b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = (on == false) and RGB(40, 42, 46) or RGB(52, 70, 58), 0.1, 0
    b.Text, b.TextSize, b.TextColor3, b.Font = s, 14, (on == false) and DIM or WHITE, BOLD
    b.AutoButtonColor = on ~= false
    b.Parent = parent
    return b
  end

  local saved = {}   -- 科技树的键 → { 弹种 = 几发 }（这一局里记着）
  local panel = nil
  local function close()
    if panel then panel:Destroy() panel = nil end
    gui.Enabled = false
  end
  G.ammoPanelOpen = function() return panel ~= nil end

  function G.openAmmo(key, nA)
    close()
    local it = TT.get and TT.get(key)
    local vid = (it and (it.veh or it.base)) or key
    local d = VD.get and VD.get(vid) or VD[vid]
    if not d then return end
    local wid = nil
    for _, w in ipairs(d.weapons or {}) do if BAL.GUN[w] then wid = w break end end
    if not wid then
      if G.toast then G.toast(T("wta2.noGun"), "info") end
      return
    end
    local w = VD.W[wid]
    local cap = (w.mag or 1) + (w.reserve or 0)
    local list = BAL.GUN[wid]
    local n = math.max(1, math.min(#list, nA or #list))
    local lay = WD.prof(d).lay
    local rcap = d.rdyN or ((lay == "e3") and 22 or ((lay == "w4") and 15 or nil))
    -- 现在的配法：配过的照旧，没配过的按默认比例
    local cur = {}
    local prev = saved[key]
    local function defaults()
      local tw = 0
      for i = 1, n do tw += SPLIT[i] or 1 end
      local sum = 0
      for i, k in ipairs(list) do
        cur[k] = (i <= n) and math.floor(cap * (SPLIT[i] or 1) / tw) or 0
        sum += cur[k]
      end
      cur[list[1]] += cap - sum
    end
    if prev then for _, k in ipairs(list) do cur[k] = prev[k] or 0 end else defaults() end
    local function total() local s = 0 for _, k in ipairs(list) do s += cur[k] or 0 end return s end

    gui.Enabled = true
    local H = 118 + #list * 40
    panel = frame(gui, UDim2.fromOffset(440, H), UD2(0.5, 0, 0.5, 0), RGB(12, 14, 17), 0.05, V2(0.5, 0.5))
    panel.Name = "AmmoPanel"
    do
      local st = Instance.new("UIStroke")
      st.Color, st.Transparency = RGB(110, 120, 126), 0.35
      st.Parent = panel
    end
    local nm = (it and G.T and T("tree." .. key)) or T("veh." .. vid)
    if nm == "tree." .. key then nm = T("veh." .. vid) end
    text(panel, nm .. "  ·  " .. T("wta2.title"), UD2(1, -24, 0, 24), UD2(0, 12, 0, 10), 16, WHITE)
    local sumT = text(panel, "", UD2(1, -24, 0, 18), UD2(0, 12, 0, 36), 13, DIM, MED)
    local rows = {}
    local function redraw()
      local s = total()
      sumT.Text = T("wta2.sum", s, cap) .. (rcap and ("   ·   " .. T("wta2.rack", math.min(rcap, math.max(0, s - 1)))) or "")
        .. ((s < cap) and ("   ·   " .. T("wta2.less")) or "")
      for _, r in ipairs(rows) do r.cnt.Text = tostring(cur[r.k] or 0) end
    end
    local function send()
      saved[key] = table.clone(cur)
      G.R.Act:FireServer("wtAmmoSet", key, cur)
      redraw()
    end
    for i, k in ipairs(list) do
      local a = BAL.AMMO[k] or {}
      local wa = WD.AMMO and WD.AMMO[k]
      local y = 62 + (i - 1) * 40
      local okType = i <= n
      local row = frame(panel, UD2(1, -24, 0, 34), UD2(0, 12, 0, y), RGB(22, 25, 29), 0.1)
      row.Name = "Ammo_" .. k
      -- 型号 + 弹种（按现在的语言：用户 11-28「弹种这些还是根据语言改变吧」；原来写 [SABOT] / [穿甲] 这种火控上的字，中英混着）
      local kd = BAL.kindOf and BAL.kindOf(k)
      local nm = (G.ammoInfo and select(1, G.ammoInfo(k))) or (BAL.desig and BAL.desig(k)) or a.name or k
      text(row, nm .. (kd and ("  ·  " .. T("ammo.t." .. kd)) or ""), UD2(0.6, 0, 1, 0), UD2(0, 8, 0, 0), 13, okType and WHITE or DIM)
      local pen = wa and wa.p0 and (math.floor(wa.p0) .. " mm") or ""
      text(row, okType and pen or T("wta2.locked"), UD2(0, 90, 1, 0), UD2(0.6, -40, 0, 0), 12, okType and GOLD or BAD, MED)
      local minus = button(row, "−", UDim2.fromOffset(30, 26), UD2(1, -112, 0, 4), okType)
      minus.Name = "Minus"
      local cnt = text(row, "0", UDim2.fromOffset(40, 34), UD2(1, -78, 0, 0), 15, WHITE, BOLD, Enum.TextXAlignment.Center)
      cnt.Name = "Count"
      local plus = button(row, "+", UDim2.fromOffset(30, 26), UD2(1, -36, 0, 4), okType)
      plus.Name = "Plus"
      local function step(sgn)
        if not okType then return end
        local by = UIS:IsKeyDown(Enum.KeyCode.LeftShift) and 5 or 1
        if sgn > 0 then by = math.min(by, cap - total()) end
        cur[k] = math.max(0, (cur[k] or 0) + sgn * by)
        send()
      end
      minus.MouseButton1Click:Connect(function() step(-1) end)
      plus.MouseButton1Click:Connect(function() step(1) end)
      table.insert(rows, { k = k, cnt = cnt })
    end
    local by = H - 46
    local b1 = button(panel, T("wta2.def"), UDim2.fromOffset(96, 32), UD2(0, 12, 0, by))
    b1.MouseButton1Click:Connect(function() defaults() send() end)
    local b2 = button(panel, T("wta2.half"), UDim2.fromOffset(96, 32), UD2(0, 116, 0, by))
    b2.MouseButton1Click:Connect(function()
      defaults()
      for _, k in ipairs(list) do cur[k] = math.floor((cur[k] or 0) / 2) end
      send()
    end)
    -- 涂装、贴花（⑯，WtSkin.lua）：机库顶栏的图标键放不下了，从配弹面板进
    if G.openSkin then
      local b4 = button(panel, T("wsk.title"), UDim2.fromOffset(110, 32), UD2(0, 216, 0, by))
      b4.Name = "SkinBtn"
      b4.MouseButton1Click:Connect(function() close() G.openSkin(key) end)
    end
    local b3 = button(panel, T("wta2.close"), UDim2.fromOffset(96, 32), UD2(1, -108, 0, by))
    b3.Name = "Close"
    b3.MouseButton1Click:Connect(close)
    redraw()
    if not prev then send() end   -- 第一次打开：把默认配法也记下（服务器按它配）
  end
  G.closeAmmo = close
  -- 出击了 / 机库关了：面板收起
  G.frameConn("WtAmmo", function()
    if panel and G.S and G.S.alive then close() end
  end)
end

return WtAmmo
