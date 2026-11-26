-- 全面大战场（客户端）——命中标记、击毁确认、击毁奖励
--   用户 11-26「击杀敌坦克准心莫名其妙会变成正方形 很难看 你自己设计一个击杀效果和音效以及奖励」：
--   原来的命中标记是一个「✕」字（Play.lua），界面字体里没有这个字形，Roblox 就画成一个方框——打掉车时那个大号的叉就成了正方形。
--   现在全用细条拼，不靠字形：
--   · 打中：准星外四根短斜杠（X，中间留空），一下弹出来再淡掉；爆头金色
--   · 击毁：斜杠更长更粗、白色；外面一圈琥珀色的环往外扩散变淡；四个折角从 45° 转正、往里收（锁定确认的感觉）
--   · 声音（Fx.lua 的 SFX：killConfirm）：一记低沉的「咚」+ 两声往上走的金属「叮」；奖励到账时一串很轻的硬币声（coinSparkle）
--   · 奖励（服务器 WtMatch.lua 发 wtKillReward）：准星右边一列依次滑进来——「击毁 · 车名」、+SP、+金币（当场到账）、+研究点（结算时发），
--     底下加成小牌：弹药殉爆、一发击毁、越级击毁；四秒后淡出，下一辆打掉时整列换新
--   G.killFxMark(kind)：Play.lua 的 G.hitMarker 调（kind：hit / head / kill / headkill / pkill / headpkill / vkill / fkill）
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local KillFx = {}

function KillFx.init(G)
  local me = Players.LocalPlayer
  local TH = G.Theme
  local RGB = Color3.fromRGB
  local V2, UD2 = Vector2.new, UDim2.new
  local L = function(zh, en) return (G.lang == "en") and en or zh end
  local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
  local WHITE, AMBER, GOLD, GREEN = RGB(255, 255, 255), TH.C.WARN, RGB(255, 206, 92), TH.C.GOOD
  local HEADC = RGB(255, 214, 90)

  local gui = Instance.new("ScreenGui")
  gui.Name = "KillFx"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 14
  gui.Parent = me:WaitForChild("PlayerGui")
  local function frame(parent, size, pos, col, tr, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position, f.AnchorPoint = size, pos or UD2(), anchor or V2()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = col or WHITE, tr or 0, 0
    f.Parent = parent
    return f
  end
  local function label(parent, s, size, pos, ts, col, font, xa)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Size, t.Position = size, pos or UD2()
    t.Text, t.TextSize, t.TextColor3, t.Font = s, ts, col, font or TH.F.bold
    t.TextXAlignment = xa or Enum.TextXAlignment.Left
    t.TextStrokeTransparency, t.TextStrokeColor3 = 0.45, RGB(0, 0, 0)
    t.Parent = parent
    return t
  end

  ---------------------------------------------------------------- 命中标记 / 击毁确认（准星上）
  local mark = frame(gui, UD2(0, 120, 0, 120), UD2(0.5, 0, 0.5, 0), WHITE, 1, V2(0.5, 0.5))
  mark.Name = "HitMark"
  mark.Visible = false
  local bars = {}
  for i = 1, 4 do   -- 四根斜杠：45°、135°、225°、315°，中间留空
    local b = frame(mark, UD2(0, 10, 0, 2), UD2(0.5, 0, 0.5, 0), WHITE, 0, V2(0.5, 0.5))
    b.Name = "Bar"
    local st = Instance.new("UIStroke")
    st.Color, st.Transparency, st.Thickness = RGB(0, 0, 0), 0.5, 1
    st.Parent = b
    bars[i] = { f = b, st = st, a = math.rad(45 + 90 * (i - 1)) }
  end
  local ring = frame(mark, UD2(0, 24, 0, 24), UD2(0.5, 0, 0.5, 0), WHITE, 1, V2(0.5, 0.5))
  ring.Name = "Ring"
  do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = ring
  end
  local ringSt = Instance.new("UIStroke")
  ringSt.Color, ringSt.Thickness = AMBER, 2
  ringSt.Parent = ring
  local brk = {}   -- 四个折角（各两根细条）：击毁时从 45° 转正、往里收
  for i = 1, 4 do
    local h = frame(mark, UD2(0, 9, 0, 2), UD2(0.5, 0, 0.5, 0), WHITE, 0, V2(0.5, 0.5))
    local v = frame(mark, UD2(0, 2, 0, 9), UD2(0.5, 0, 0.5, 0), WHITE, 0, V2(0.5, 0.5))
    h.Name, v.Name = "Corner", "Corner"
    brk[i] = { h = h, v = v, sx = (i == 1 or i == 4) and -1 or 1, sy = (i <= 2) and -1 or 1 }
  end
  local M = { t0 = -10, kind = "hit", kill = false, head = false }
  local function place(r, len, th, rot, col, tr)
    for _, b in ipairs(bars) do
      local a = b.a
      b.f.Size = UD2(0, len, 0, th)
      b.f.Position = UD2(0.5, math.cos(a) * (r + len / 2), 0.5, math.sin(a) * (r + len / 2))
      b.f.Rotation = math.deg(a) + (rot or 0)
      b.f.BackgroundColor3 = col
      b.f.BackgroundTransparency = tr
      b.st.Transparency = 0.5 + 0.5 * tr
    end
  end
  local function ease(q) q = math.clamp(q, 0, 1) return 1 - (1 - q) ^ 3 end
  local function step()
    local t = os.clock() - M.t0
    local dur = M.kill and 1.0 or 0.34
    if t > dur then mark.Visible = false return end
    mark.Visible = true
    mark.Position = G.hitMarkerAt or UD2(0.5, 0, 0.5, 0)   -- 开飞机时标在炮口指的地方（Fly.lua 每帧设）
    local col = M.head and HEADC or WHITE
    if M.kill then
      -- 斜杠：先弹大（0.07 秒）再回到常态，0.6 秒后淡出
      local pop = 1 + 0.35 * (1 - ease(t / 0.09))
      local tr = math.clamp((t - 0.6) / 0.4, 0, 1)
      place(9 * pop, 13 * pop, 3, 0, col, tr)
      -- 环：从 24 扩到 84，越扩越淡
      local q = ease(t / 0.5)
      local d = 24 + 60 * q
      ring.Size = UD2(0, d, 0, d)
      ring.Visible = true
      ringSt.Transparency = math.clamp(0.1 + 0.9 * q, 0, 1)
      ringSt.Thickness = 2.5 - 1.5 * q
      -- 折角：0.18 秒里从半径 34、斜 45° 收到半径 22、转正，停一会儿再淡
      local k = ease(t / 0.18)
      local rr = 34 - 12 * k
      local rot = 45 * (1 - k)
      local ctr = math.clamp((t - 0.55) / 0.4, 0, 1)
      for _, c in ipairs(brk) do
        local cx, cy = c.sx * rr, c.sy * rr
        local ca, sa = math.cos(math.rad(rot)), math.sin(math.rad(rot))
        local px, py = cx * ca - cy * sa, cx * sa + cy * ca
        c.h.Position = UD2(0.5, px - c.sx * 3.5, 0.5, py)
        c.v.Position = UD2(0.5, px, 0.5, py - c.sy * 3.5)
        c.h.Rotation, c.v.Rotation = rot, rot
        c.h.BackgroundTransparency, c.v.BackgroundTransparency = ctr, ctr
        c.h.Visible, c.v.Visible = true, true
      end
    else
      local pop = 1 + 0.3 * (1 - ease(t / 0.06))
      local tr = math.clamp((t - 0.08) / 0.26, 0, 1)
      place(7 * pop, 8 * pop, 2, 0, col, tr)
      ring.Visible = false
      for _, c in ipairs(brk) do c.h.Visible, c.v.Visible = false, false end
    end
  end
  if G.frameConn then G.frameConn("killfx", step) else RunService.RenderStepped:Connect(step) end

  function G.killFxMark(kind)
    kind = tostring(kind or "hit")
    M.t0 = os.clock()
    M.kind = kind
    M.kill = string.find(kind, "kill") ~= nil
    M.head = string.find(kind, "head") ~= nil
    step()
    if M.kill then
      if G.sfx then G.sfx("killConfirm", nil, { must = true }) elseif G.playSound then G.playSound("killding") end
    elseif G.playSound then
      G.playSound("hit")
    end
  end
  G.killFxState = function() return { kill = M.kill, t = os.clock() - M.t0, shown = mark.Visible } end   -- 测试用

  ---------------------------------------------------------------- 击毁奖励（准星右边一列）
  local RW = mobile and 210 or 260
  local panel = frame(gui, UD2(0, RW, 0, 150), UD2(0.5, mobile and 54 or 74, 0.5, -36), WHITE, 1)
  panel.Name = "KillReward"
  panel.Visible = false
  local rows = {}
  local function row(y, h)
    local f = frame(panel, UD2(1, 0, 0, h), UD2(0, 0, 0, y), WHITE, 1)
    table.insert(rows, f)
    return f
  end
  local r1 = row(0, 28)
  local killT = label(r1, L("击毁", "DESTROYED"), UD2(0, 70, 1, 0), nil, mobile and 20 or 24, WHITE, TH.F.title)
  killT.Name = "Title"
  local vehT = label(r1, "", UD2(1, -74, 1, -4), UD2(0, 74, 0, 4), TH.S.body, TH.C.MUTE, TH.F.bold)
  vehT.Name = "Veh"
  vehT.TextTruncate = Enum.TextTruncate.AtEnd
  local underline = frame(panel, UD2(0, 0, 0, 2), UD2(0, 0, 0, 31), AMBER, 0)
  underline.Name = "Line"
  local lines = {}
  local function amountRow(y, col, name)
    local f = row(y, 22)
    f.Name = name
    local v = label(f, "", UD2(0, 90, 1, 0), nil, mobile and 17 or 19, col, TH.F.mono)
    v.Name = "Val"
    local lb = label(f, "", UD2(1, -96, 1, 0), UD2(0, 96, 0, 0), TH.S.small, TH.C.MUTE, TH.F.bold)
    lb.Name = "Lbl"
    lines[name] = { f = f, v = v, lb = lb }
  end
  amountRow(38, AMBER, "SP")
  amountRow(62, GOLD, "Coins")
  amountRow(86, GREEN, "RP")
  local tagRow = row(114, 22)
  tagRow.Name = "Tags"
  local TAGS = { ammo = L("弹药殉爆", "Ammo detonation"), one = L("一发击毁", "One-shot"), up = L("越级击毁", "Higher BR") }
  local R = { t0 = -10, order = {} }
  local function show(m)
    local vn = nil
    if m.vk and G.T then vn = G.T("tree." .. m.vk) if vn == "tree." .. m.vk then vn = nil end end
    if not vn and m.vv and G.T then vn = G.T("veh." .. m.vv) end
    vehT.Text = vn or ""
    killT.Text = m.air and L("击落", "SHOT DOWN") or L("击毁", "DESTROYED")
    local order = { rows[1] }
    local function amt(name, n, lbl)
      local x = lines[name]
      x.f.Visible = (n or 0) > 0
      x.v.Text = "+" .. tostring(n or 0)
      x.lb.Text = lbl
      if x.f.Visible then table.insert(order, x.f) end
    end
    amt("SP", m.sp, "SP")
    amt("Coins", m.coins, L("金币", "Coins"))
    amt("RP", m.rp, L("研究点 · 结算时发", "Research · at round end"))
    -- 加成小牌
    for _, c in ipairs(tagRow:GetChildren()) do c:Destroy() end
    local x = 0
    for _, k in ipairs(m.tags or {}) do
      local txt = TAGS[k]
      if txt then
        local w = 14 + #txt * (G.lang == "en" and 7 or 5)
        local chip = frame(tagRow, UD2(0, w, 0, 20), UD2(0, x, 0, 0), RGB(0, 0, 0), 0.4)
        TH.corner(chip, 2)
        local st = Instance.new("UIStroke")
        st.Color, st.Transparency, st.Thickness = AMBER, 0.2, 1
        st.Parent = chip
        local t = label(chip, txt, UD2(1, 0, 1, 0), nil, TH.S.tiny, AMBER, TH.F.bold, Enum.TextXAlignment.Center)
        t.Name = "Tag"
        x += w + 6
      end
    end
    tagRow.Visible = x > 0
    if tagRow.Visible then table.insert(order, tagRow) end
    -- 排好：一行行往下摆（没有的那行不占位）
    local y = 0
    for i, f in ipairs(order) do
      if i == 2 then y += 8 end   -- 标题和金额之间留出下划线的位置
      f.Position = UD2(0, 0, 0, y)
      y += f.Size.Y.Offset + 2
    end
    R.order = order
    R.t0 = os.clock()
    panel.Visible = true
    if G.sfx and ((m.coins or 0) > 0 or (m.rp or 0) > 0) then G.sfx("coinSparkle", nil, { delay = 0.28 }) end
  end
  local function stepR()
    if not panel.Visible then return end
    local t = os.clock() - R.t0
    if t > 4.4 then panel.Visible = false return end
    local out = math.clamp((t - 3.8) / 0.6, 0, 1)
    underline.Size = UD2(0, math.floor((RW - 40) * ease(t / 0.35)), 0, 2)
    underline.BackgroundTransparency = out
    for i, f in ipairs(R.order) do
      local q = ease((t - 0.06 * (i - 1)) / 0.22)
      f.Position = UD2(0, 24 * (1 - q), 0, f.Position.Y.Offset)
      for _, d in ipairs(f:GetDescendants()) do
        if d:IsA("TextLabel") then d.TextTransparency = math.max(1 - q, out) d.TextStrokeTransparency = math.max(0.45, math.max(1 - q, out)) end
        if d:IsA("Frame") then d.BackgroundTransparency = math.max(d.Name == "" and 1 or 0.4, math.max(1 - q, out)) end
        if d:IsA("UIStroke") then d.Transparency = math.max(0.2, math.max(1 - q, out)) end
      end
      if f:IsA("TextLabel") then f.TextTransparency = math.max(1 - q, out) end
    end
  end
  if G.frameConn then G.frameConn("killreward", stepR) else RunService.RenderStepped:Connect(stepR) end
  G.killRewardShow = show   -- 测试用
  G.killRewardState = function() return { shown = panel.Visible, veh = vehT.Text, sp = lines.SP.v.Text, coins = lines.Coins.v.Text, rp = lines.RP.v.Text,
    tags = #tagRow:GetChildren() } end
  if G.R and G.R.Drive then
    G.R.Drive.OnClientEvent:Connect(function(m)
      if type(m) == "table" and m.op == "wtKillReward" then G.try_(show, m) end
    end)
  end
end

return KillFx
