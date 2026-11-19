-- Roblox全面大战场（客户端）——爽感（用户：同时想办法增加玩家体验感和爽感）
--   ① 加分滚动（准星右边）：每次打死、摧毁、占领弹一行「+60 击杀」，上面一个大数字累计；2.5 秒没新的就淡出清零
--   ② 爆头：头盔上「叮」一声脆响，加分行里多一行金色的「爆头」
--   ③ 连杀：4.5 秒内接着打死——屏幕上方「双杀！三杀！四杀！N 连杀！」，一声往上走的提示音；
--      一条命里连着打死 5 / 10 / 15 个：「势不可挡 / 杀戮机器 / 战场之王」大横幅，死了清零
--   ④ 受伤方向：挨打时准星周围一道红弧指向开枪的人（炸的指向炸点），一秒多淡出
--   ⑤ 低血量：三成血以下屏幕四周发红、画面发灰，心跳一下一下（血越少越快）
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Juice = {}

function Juice.init(G)
  local Config = G.Config
  local me = Players.LocalPlayer
  local pg = me:WaitForChild("PlayerGui")
  local V2, RGB = Vector2.new, Color3.fromRGB
  local SC = Config.Score
  local function T(k, ...) return G.T(k, ...) end
  local now = os.clock

  local gui = Instance.new("ScreenGui")
  gui.Name = "Juice"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 9
  gui.Parent = pg
  local function label(parent, text, size, pos, ts, color, font, anchor, align)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size, l.Position = size, pos
    l.AnchorPoint = anchor or V2(0, 0.5)
    l.Text = text
    l.TextSize = ts
    l.TextColor3 = color
    l.Font = font or Enum.Font.GothamBold
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.TextStrokeTransparency = 0.45
    l.Parent = parent
    return l
  end

  ---------------------------------------------------------------- ① 加分滚动

  local ticker = Instance.new("Frame")
  ticker.Name = "Ticker"
  ticker.BackgroundTransparency = 1
  ticker.Size = UDim2.fromOffset(260, 150)
  ticker.Position = UDim2.new(0.5, 64, 0.5, -42)
  ticker.Parent = gui
  local total = label(ticker, "", UDim2.fromOffset(240, 34), UDim2.fromOffset(0, 16), 28, RGB(255, 222, 120), Enum.Font.GothamBlack)
  total.Name = "Total"
  local tScale = Instance.new("UIScale")
  tScale.Parent = total
  local lines, sum, lastT = {}, 0, -1e9
  local function relayout()
    for i, l in ipairs(lines) do
      if l.Parent then l.Position = UDim2.fromOffset(2, 40 + (i - 1) * 21) end
    end
  end
  local function addLine(text, color)
    local l = label(ticker, text, UDim2.fromOffset(240, 20), UDim2.fromOffset(2, 40), 16, color or Color3.new(1, 1, 1))
    l.Name = "Line"
    table.insert(lines, 1, l)
    while #lines > 4 do table.remove(lines):Destroy() end
    relayout()
  end
  -- 加 pts 分、一行说明（pts 为 0 只加一行字，比如「爆头」）
  function G.juiceScore(pts, text, color)
    if now() - lastT > 2.5 then sum = 0 end
    sum += pts or 0
    lastT = now()
    total.Text = (sum > 0) and ("+" .. sum) or ""
    total.TextTransparency, total.TextStrokeTransparency = 0, 0.45
    tScale.Scale = 1.35
    TweenService:Create(tScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
    addLine(((pts or 0) > 0 and ("+" .. pts .. "  ") or "") .. text, color)
  end

  ---------------------------------------------------------------- ③ 连杀横幅

  local banner = label(gui, "", UDim2.fromOffset(700, 60), UDim2.fromScale(0.5, 0.24), 44, RGB(255, 236, 170), Enum.Font.GothamBlack, V2(0.5, 0.5), Enum.TextXAlignment.Center)
  banner.Name = "Banner"
  banner.TextStrokeTransparency = 0.2
  banner.TextTransparency = 1
  local sub = label(gui, "", UDim2.fromOffset(500, 26), UDim2.new(0.5, 0, 0.24, 38), 18, RGB(255, 200, 120), Enum.Font.GothamBold, V2(0.5, 0.5), Enum.TextXAlignment.Center)
  sub.Name = "BannerSub"
  sub.TextTransparency = 1
  local bScale = Instance.new("UIScale")
  bScale.Parent = banner
  local bannerT = -1e9
  local function showBanner(text, small)
    banner.Text, sub.Text = text, small or ""
    banner.TextTransparency, banner.TextStrokeTransparency = 0, 0.2
    sub.TextTransparency, sub.TextStrokeTransparency = 0, 0.5
    bScale.Scale = 1.6
    TweenService:Create(bScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
    bannerT = now()
    if G.sfx then G.sfx("streak", nil, { vol = 0.9 }) end
    if G.shake then G.shake(0.12) end
  end
  local kills, life = {}, 0
  local MULTI = { [2] = "juice.x2", [3] = "juice.x3", [4] = "juice.x4" }
  local LIFE = { [5] = "juice.s5", [10] = "juice.s10", [15] = "juice.s15" }

  ---------------------------------------------------------------- 命中、打死（Play.lua 的 G.hitMarker 调）

  function G.juiceHit(kind)
    local kill = string.find(kind, "kill") ~= nil
    local head = string.find(kind, "head") ~= nil
    if head and G.sfx then G.sfx("headshot", nil, { vol = kill and 1.1 or 0.8 }) end
    if not kill then return end
    local pts, what = SC.botKill, T("juice.kill")
    if kind == "pkill" or kind == "headpkill" then pts = SC.kill
    elseif kind == "vkill" then pts, what = SC.vehicleKill, T("juice.vkill")
    elseif kind == "fkill" then pts, what = SC.fortKill, T("juice.fkill") end
    G.juiceScore(pts, what)
    if head then G.juiceScore(0, T("juice.head"), RGB(255, 205, 80)) end
    -- 连杀：4.5 秒内接着打死的算一串
    local t = now()
    for i = #kills, 1, -1 do if t - kills[i] > 4.5 then table.remove(kills, i) end end
    table.insert(kills, t)
    life += 1
    local n = #kills
    if LIFE[life] then
      showBanner(T(LIFE[life]), T("juice.streak", life))
    elseif n >= 2 then
      showBanner(MULTI[n] and T(MULTI[n]) or T("juice.xn", n))
    end
  end
  G.juiceState = function() return { sum = sum, life = life, multi = #kills } end   -- 测试用

  ---------------------------------------------------------------- ④ 受伤方向

  local hurtArcs = {}
  for i = 1, 6 do
    local f = Instance.new("Frame")
    f.Name = "HurtArc"
    f.AnchorPoint = V2(0.5, 0.5)
    f.Size = UDim2.fromOffset(74, 9)
    f.BackgroundColor3 = RGB(230, 40, 30)
    f.BorderSizePixel = 0
    f.BackgroundTransparency = 1
    f.Visible = false
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent = f
    local gr = Instance.new("UIGradient")   -- 两头淡、中间浓：像一道弧
    gr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
    gr.Parent = f
    f.Parent = gui
    hurtArcs[i] = { f = f, t = -1e9, pos = nil }
  end
  local hurtN = 0
  function G.juiceHurt(pos)
    hurtN = hurtN % #hurtArcs + 1
    local a = hurtArcs[hurtN]
    a.t, a.pos = now(), pos
    a.f.Visible = true
  end

  ---------------------------------------------------------------- ⑤ 低血量

  local edges = {}
  for _, side in ipairs({ { V2(0, 0), UDim2.new(1, 0, 0.22, 0), 90 }, { V2(0, 1), UDim2.new(1, 0, 0.22, 0), -90 }, { V2(0, 0), UDim2.new(0.18, 0, 1, 0), 0 }, { V2(1, 0), UDim2.new(0.18, 0, 1, 0), 180 } }) do
    local f = Instance.new("Frame")
    f.Name = "LowHp"
    f.AnchorPoint = side[1]
    f.Position = UDim2.fromScale(side[1].X, side[1].Y)
    f.Size = side[2]
    f.BackgroundColor3 = RGB(150, 0, 0)
    f.BorderSizePixel = 0
    f.Visible = false
    local gr = Instance.new("UIGradient")
    gr.Rotation = side[3]
    gr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
    gr.Parent = f
    f.Parent = gui
    table.insert(edges, f)
  end
  local cc = Instance.new("ColorCorrectionEffect")
  cc.Name = "JuiceLowHp"
  cc.Enabled = false
  cc.Parent = Lighting
  local beatT = 0

  ---------------------------------------------------------------- 每帧

  local lastAlive = true
  G.frameConn("Juice", function(dt)
    local t = now()
    -- 加分滚动：2.5 秒没新的就淡出
    local a = t - lastT
    if a > 2.5 and total.Text ~= "" then
      local k = math.clamp((a - 2.5) / 0.5, 0, 1)
      total.TextTransparency, total.TextStrokeTransparency = k, 0.45 + 0.55 * k
      for _, l in ipairs(lines) do l.TextTransparency, l.TextStrokeTransparency = k, 0.45 + 0.55 * k end
      if k >= 1 then
        total.Text = ""
        for _, l in ipairs(lines) do l:Destroy() end
        lines = {}
      end
    end
    -- 横幅：1.6 秒后淡出
    local b = t - bannerT
    if b > 1.6 and banner.TextTransparency < 1 then
      local k = math.clamp((b - 1.6) / 0.5, 0, 1)
      banner.TextTransparency, banner.TextStrokeTransparency = k, 0.2 + 0.8 * k
      sub.TextTransparency, sub.TextStrokeTransparency = k, 0.5 + 0.5 * k
    end
    -- 受伤方向：按伤害来的方向（相对镜头的水平方位）摆在准星周围一圈上
    local cam = workspace.CurrentCamera
    local cf = cam.CFrame
    for _, h in ipairs(hurtArcs) do
      if h.f.Visible then
        local age = t - h.t
        if age > 1.4 or not h.pos then
          h.f.Visible = false
        else
          local d = h.pos - cf.Position
          local x, z = d:Dot(cf.RightVector), d:Dot(Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit)
          local ang = math.atan2(x, z)   -- 0 正前、正的在右边
          local r = 120
          h.f.Position = UDim2.new(0.5, math.sin(ang) * r, 0.5, -math.cos(ang) * r)
          h.f.Rotation = math.deg(ang)
          h.f.BackgroundTransparency = 0.1 + 0.9 * math.clamp((age - 0.6) / 0.8, 0, 1)
        end
      end
    end
    -- 低血量
    local char = me.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local f = 1
    if hum and hum.MaxHealth > 0 and hum.Health > 0 then f = hum.Health / hum.MaxHealth end
    local low = (f < 0.35) and (0.35 - f) / 0.35 or 0
    local inVeh = G.drive ~= nil or G.fly ~= nil
    if inVeh then low = 0 end
    local on = low > 0.01
    for _, e in ipairs(edges) do
      e.Visible = on
      if on then e.BackgroundTransparency = 1 - (0.25 + 0.45 * low) * (0.75 + 0.25 * math.sin(t * (5 + 6 * low))) end
    end
    cc.Enabled = on
    if on then
      cc.Saturation = -0.55 * low
      cc.TintColor = Color3.new(1, 1 - 0.18 * low, 1 - 0.18 * low)
      if t >= beatT then
        beatT = t + 1.1 - 0.5 * low
        if G.sfx then G.sfx("heart", nil, { vol = 0.6 + 0.6 * low }) end
      end
    end
    -- 死了：一条命的连杀清零
    local alive = hum ~= nil and hum.Health > 0
    if lastAlive and not alive then life, kills = 0, {} end
    lastAlive = alive
  end)
end

return Juice
