-- 全面大战场（客户端）——游戏设置（用户 11-25「设置一个兑换码 在设置里」「那个设置界面不好看 重做」，又发了截图「设置界面要能这样」）
--   整屏一页（机库顶栏的齿轮打开，打仗时按 F10）：背后的机库压暗、模糊；左上「‹ 机库 | 游戏设置」（点「机库」返回），右上 ×；
--   顶上一条搜索框（打字就把所有分类里名字对得上的项列出来）；左边「导航」一列分类，右边一行一项：名字靠右 + 控件（下拉框、滑块、勾选、按钮）；
--   右下「关闭」。外观照 docs/style.md（深色、细白线、2 像素圆角、选中的白底黑字）。分类和项：
--   · 主要参数：语言（简体中文 / English：多数界面重新进入游戏后才换）、界面比例（紧凑 / 标准 / 大 / 特大：机库、设置整体放大，字更清楚）、灰度校正
--   · 操作设置：鼠标灵敏度、开镜灵敏度（瞄准镜 / 光电里再乘一次）、反转鼠标上下——G.mouseDelta(开镜) 给 Drive / Fly / Gunner / Sail 用
--   · 陆战设置：第三人称视野（G.fov3）、镜头晃动（G.noShake）；空战设置：飞机 / 直升机第三人称视野（G.fov3Air）
--   · 声音：总音量（SoundService 里一个 Master 声音组，所有声音挂上去）、车组语音（G.voiceOff，WtVoice）
--   · 兑换码：输入框 + 「兑换」，服务器 Tech.lua ACT.redeem 判（码只在服务器上）；结果从玩家属性 Redeem 读回来写在下面
--   设置存在服务器存档里（Store.lua ACT.prefs → 玩家属性 Prefs），换台电脑也一样；拖滑块时 0.4 秒没再动才发一次
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Http = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local Settings = {}

function Settings.init(G)
  local me = Players.LocalPlayer
  local TH = G.Theme
  local UD2, V2 = UDim2.new, Vector2.new
  local zh = G.lang ~= "en"
  local function L(a, b) return zh and a or b end
  local function act(...)
    local args = table.pack(...)
    pcall(function() G.R.Act:FireServer(table.unpack(args, 1, args.n)) end)
  end

  ---------------------------------------------------------------- 设置项和默认值
  local DEF = { sens = 1, aim = 1, invY = false, fov = 70, fovAir = 70, shake = true, vol = 1, voice = true, ui = 1, gamma = 0, lang = "" }
  local P = {}
  for k, v in pairs(DEF) do P[k] = v end

  -- 总音量：SoundService 里的 Master 声音组，所有声音挂上去（已经有声音组的不动）
  local master = nil
  pcall(function()
    local SS = game:GetService("SoundService")
    master = SS:FindFirstChild("Master") or Instance.new("SoundGroup")
    master.Name = "Master"
    master.Parent = SS
  end)
  local function hook(o)
    if master and o:IsA("Sound") and o.SoundGroup == nil then pcall(function() o.SoundGroup = master end) end
  end
  if master then
    pcall(function()
      for _, o in ipairs(workspace:GetDescendants()) do hook(o) end
      workspace.DescendantAdded:Connect(hook)
      local pg = me:WaitForChild("PlayerGui", 5)
      if pg then
        for _, o in ipairs(pg:GetDescendants()) do hook(o) end
        pg.DescendantAdded:Connect(hook)
      end
      local SS = game:GetService("SoundService")
      for _, o in ipairs(SS:GetDescendants()) do hook(o) end
      SS.DescendantAdded:Connect(hook)
    end)
  end
  -- 灰度校正：自己的一层调色（Lighting 里别的调色照旧）
  local gammaCC = nil
  pcall(function()
    gammaCC = Instance.new("ColorCorrectionEffect")
    gammaCC.Name = "UserGamma"
    gammaCC.Parent = Lighting
  end)
  -- 打开设置时背后模糊（同截图：机库糊成一片）
  local blur = nil
  pcall(function()
    blur = Instance.new("BlurEffect")
    blur.Name = "SettingsBlur"
    blur.Size = 14
    blur.Enabled = false
    blur.Parent = Lighting
  end)
  -- 模糊淡进淡出（11-27「动画做出丝滑感」：原来一下子 0 → 14）：开 0.2 秒、关 0.12 秒；关完了把效果关掉。系统开了「减少动态效果」就直接开关
  local TweenService = game:GetService("TweenService")
  local BLUR_IN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
  local BLUR_OUT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
  local blurTok = 0
  local function blurTo(on)
    if not blur then return end
    blurTok += 1
    local still = G.reducedMotion and G.reducedMotion()
    if on then
      if not blur.Enabled then blur.Size = still and 14 or 0 end
      blur.Enabled = true
      if not still then TweenService:Create(blur, BLUR_IN, { Size = 14 }):Play() end
    else
      if not blur.Enabled then return end
      if still then blur.Enabled = false return end
      local tok = blurTok
      TweenService:Create(blur, BLUR_OUT, { Size = 0 }):Play()
      task.delay(BLUR_OUT.Time, function()
        if blurTok == tok then blur.Enabled = false blur.Size = 14 end
      end)
    end
  end

  G.uiRefit = G.uiRefit or {}   -- 界面比例变了要重新排的（TechUI 的机库、这一页）
  local function apply()
    G.sensK, G.aimSensK, G.invertY = P.sens, P.aim, P.invY == true
    G.fov3, G.fov3Air = P.fov, P.fovAir
    G.noShake = P.shake == false
    G.voiceOff = P.voice == false
    if master then pcall(function() master.Volume = P.vol end) end
    -- 灰度是 0（默认）就把这层调色关掉（11-27 M3 丝滑：亮度、对比都是 0 也开着是白画一遍全屏后期）
    if gammaCC then pcall(function() gammaCC.Brightness = P.gamma gammaCC.Contrast = math.abs(P.gamma) * 0.4 gammaCC.Enabled = math.abs(P.gamma) > 1e-3 end) end
    if P.lang == "zh" or P.lang == "en" then G.lang = P.lang end
    if G.uiScaleK ~= P.ui then
      G.uiScaleK = P.ui
      for _, f in ipairs(G.uiRefit) do pcall(f) end
    end
  end
  apply()
  -- 鼠标这一帧挪了多少（已经乘过灵敏度、开镜灵敏度，反转了 Y）
  function G.mouseDelta(aim)
    local d = UIS:GetMouseDelta()
    local k = (G.sensK or 1) * (aim and (G.aimSensK or 1) or 1)
    return V2(d.X * k, d.Y * k * (G.invertY and -1 or 1))
  end

  local function readPrefs()
    local s = me:GetAttribute("Prefs")
    if type(s) ~= "string" then return end
    local ok, t = pcall(function() return Http:JSONDecode(s) end)
    if not ok or type(t) ~= "table" then return end
    for k, v in pairs(DEF) do
      if type(t[k]) == type(v) then P[k] = t[k] end
    end
    apply()
  end
  readPrefs()

  local sendAt = nil
  local function changed()
    apply()
    sendAt = os.clock() + 0.4
  end
  task.spawn(function()
    while true do
      task.wait(0.2)
      if sendAt and os.clock() >= sendAt then
        sendAt = nil
        local t = {}
        for k in pairs(DEF) do t[k] = P[k] end
        act("prefs", t)
      end
    end
  end)

  ---------------------------------------------------------------- 界面
  local gui = Instance.new("ScreenGui")
  gui.Name = "Settings"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 30   -- 在机库（12）、观战（15）上面
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")

  local function frame(parent, size, pos, col, tr)
    local f = Instance.new("Frame")
    f.Size, f.Position = size, pos or UD2()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = col or TH.C.PANEL, tr or 0, 0
    f.Parent = parent
    return f
  end
  local function text(parent, s, size, pos, ts, col, font, align)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Size, t.Position = size, pos or UD2()
    t.Text, t.TextSize, t.TextColor3 = s, ts or TH.S.body, col or TH.C.TEXT
    t.Font = font or TH.F.body
    t.TextXAlignment = align or Enum.TextXAlignment.Left
    t.TextTruncate = Enum.TextTruncate.AtEnd
    t.Parent = parent
    return t
  end
  local function btn(parent, s, size, pos, ts)
    local b = Instance.new("TextButton")
    b.Size, b.Position = size, pos or UD2()
    b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = TH.C.RAISE, 0.15, 0
    b.AutoButtonColor = true
    b.Text, b.Font, b.TextSize, b.TextColor3 = s, TH.F.body, ts or TH.S.body, TH.C.TEXT
    b.Parent = parent
    TH.corner(b)
    TH.stroke(b)
    return b
  end

  -- 整屏压暗；内容按 1280 × 720 画，窗口大小、界面比例变了整体缩放
  local dim = frame(gui, UD2(1, 0, 1, 0), nil, TH.C.BG, 0.3)
  dim.Name = "Dim"
  dim.Active = true   -- 挡住后面机库的点击
  local root = frame(gui, UD2(1, 0, 1, 0), nil, nil, 1)
  root.Name = "Root"
  local sc = Instance.new("UIScale")
  sc.Parent = root
  local VW, VH = 1280, 720
  local function fit()
    local c = workspace.CurrentCamera
    local vp = c and c.ViewportSize or V2(1280, 720)
    local s = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.5, 2.2) * (G.uiScaleK or 1)
    sc.Scale = s
    root.Size = UD2(1 / s, 0, 1 / s, 0)
    VW, VH = vp.X / s, vp.Y / s
  end
  fit()
  table.insert(G.uiRefit, fit)
  do
    local c = workspace.CurrentCamera
    if c then c:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end
  end

  -- 左上：「‹ 机库 | 游戏设置」；右上 ×；底下一道细线
  local back = Instance.new("TextButton")
  back.Name = "Back"
  back.BackgroundTransparency, back.AutoButtonColor = 1, false
  back.Size, back.Position = UD2(0, 70, 0, 22), UD2(0, 28, 0, 30)
  back.Text, back.Font, back.TextSize, back.TextColor3 = "< " .. L("机库", "Hangar"), TH.F.body, TH.S.body, TH.C.MUTE
  back.TextXAlignment = Enum.TextXAlignment.Left
  back.Parent = root
  text(root, "|", UD2(0, 10, 0, 22), UD2(0, 96, 0, 30), TH.S.body, TH.C.FAINT)
  local head = text(root, L("游戏设置", "Game settings"), UD2(0, 300, 0, 34), UD2(0, 112, 0, 24), TH.S.big, TH.C.TEXT, TH.F.title)
  head.Name = "Title"
  local closeX = Instance.new("TextButton")
  closeX.Name = "Close"
  closeX.Size, closeX.Position = UD2(0, 34, 0, 34), UD2(1, -58, 0, 22)
  closeX.BackgroundTransparency, closeX.AutoButtonColor = 1, false
  closeX.Text, closeX.Font, closeX.TextSize, closeX.TextColor3 = "×", TH.F.body, 30, TH.C.TEXT
  closeX.Parent = root
  frame(root, UD2(1, -48, 0, 1), UD2(0, 24, 0, 66), TH.C.LINE, TH.A.line)

  -- 搜索框（顶上一整条）
  local search = Instance.new("TextBox")
  search.Name = "Search"
  search.Size, search.Position = UD2(1, -330, 0, 30), UD2(0, 300, 0, 80)
  search.BackgroundColor3, search.BackgroundTransparency, search.BorderSizePixel = TH.C.BG, 0.25, 0
  search.Font, search.TextSize, search.TextColor3 = TH.F.body, TH.S.body, TH.C.TEXT
  search.PlaceholderText = L("搜索设置……", "Search settings…")
  search.PlaceholderColor3 = TH.C.FAINT
  search.Text, search.ClearTextOnFocus = "", false
  search.TextXAlignment = Enum.TextXAlignment.Left
  search.Parent = root
  TH.corner(search)
  TH.stroke(search)
  do
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 12)
    pad.Parent = search
  end

  -- 左边导航
  text(root, L("导航", "Navigation"), UD2(0, 236, 0, 22), UD2(0, 24, 0, 82), TH.S.sub, TH.C.TEXT, TH.F.bold, Enum.TextXAlignment.Center)
  local CATS = {
    { key = "main", zh = "主要参数", en = "Main" },
    { key = "ctl", zh = "操作设置", en = "Controls" },
    { key = "ground", zh = "陆战设置", en = "Ground battles" },
    { key = "air", zh = "空战设置", en = "Air battles" },
    { key = "snd", zh = "声音", en = "Sound" },
    { key = "code", zh = "兑换码", en = "Redeem code" },
  }
  local navBtns = {}
  local cur = "main"
  local content = frame(root, UD2(1, -330, 1, -200), UD2(0, 300, 0, 126), nil, 1)
  content.Name = "Content"
  content.ClipsDescendants = true

  -- 设置项：分类、键、名字、说明、类型（drop 下拉 / slider 滑块 / check 勾选 / code 兑换码）、参数
  local function pct(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
  local function mult(v) return string.format("%.2f×", v) end
  local function deg(v) return string.format("%d°", v) end
  local ITEMS = {
    { cat = "main", key = "lang", kind = "drop", zh = "语言（Language）", en = "Language",
      opts = { { "", L("跟随系统", "System") }, { "zh", "简体中文" }, { "en", "English" } },
      note = L("多数界面重新进入游戏后才换", "Most screens switch after rejoining") },
    { cat = "main", key = "ui", kind = "drop", zh = "界面比例", en = "Interface scale",
      opts = { { 0.85, L("紧凑（85%）", "Compact (85%)") }, { 1, L("标准（100%）", "Standard (100%)") }, { 1.15, L("大（115%）", "Large (115%)") }, { 1.3, L("特大（130%）", "Extra large (130%)") } },
      note = L("机库、科技树、设置整体放大，字更清楚", "Scales the hangar, tech tree and settings") },
    { cat = "main", key = "gamma", kind = "slider", zh = "灰度校正", en = "Brightness", lo = -0.1, hi = 0.1, step = 0.01, fmt = function(v) return string.format("%+.2f", v) end },
    { cat = "ctl", key = "sens", kind = "slider", zh = "鼠标灵敏度", en = "Mouse sensitivity", lo = 0.25, hi = 2.5, step = 0.05, fmt = mult },
    { cat = "ctl", key = "aim", kind = "slider", zh = "开镜灵敏度", en = "Aim sensitivity", lo = 0.25, hi = 2, step = 0.05, fmt = mult,
      note = L("瞄准镜、光电吊舱里再乘一次", "Extra factor in sights and pods") },
    { cat = "ctl", key = "invY", kind = "check", zh = "反转鼠标上下", en = "Invert mouse Y" },
    { cat = "ground", key = "fov", kind = "slider", zh = "第三人称视野（载具）", en = "Chase camera FOV (vehicles)", lo = 60, hi = 90, step = 1, fmt = deg },
    { cat = "ground", key = "shake", kind = "check", zh = "镜头晃动", en = "Camera shake", note = L("爆炸、开炮、路面颠簸", "Explosions, gunfire, rough ground") },
    { cat = "air", key = "fovAir", kind = "slider", zh = "第三人称视野（飞机、直升机）", en = "Chase camera FOV (aircraft)", lo = 60, hi = 90, step = 1, fmt = deg },
    { cat = "snd", key = "vol", kind = "slider", zh = "总音量", en = "Master volume", lo = 0, hi = 1, step = 0.05, fmt = pct },
    { cat = "snd", key = "voice", kind = "check", zh = "车组语音", en = "Crew voice", note = L("装填完毕、发现敌人、被击中……", "Loaded, enemy spotted, hit…") },
    { cat = "code", key = "code", kind = "code", zh = "兑换码", en = "Redeem code" },
  }

  local rows = {}   -- [key] = 刷新函数
  local openDrop = nil   -- 开着的下拉列表（点别处收起）
  local LX, CX, CW = 360, 380, 360   -- 名字靠右到 LX；控件从 CX 起、宽 CW
  -- 一行：名字（靠右）、控件、说明（控件下面一行小字）
  local function rowBase(parent, y, it)
    local r = frame(parent, UD2(1, 0, 0, it.note and 50 or 36), UD2(0, 0, 0, y), nil, 1)
    r.Name = "Row_" .. it.key
    text(r, L(it.zh, it.en), UD2(0, LX, 0, 28), UD2(0, 0, 0, 2), TH.S.body, TH.C.TEXT, TH.F.body, Enum.TextXAlignment.Right)
    if it.note then text(r, it.note, UD2(0, CW + 120, 0, 16), UD2(0, CX, 0, 32), TH.S.small, TH.C.MUTE) end
    return r
  end
  local function buildRow(parent, y, it)
    local r = rowBase(parent, y, it)
    local key = it.key
    if it.kind == "slider" then
      local track = frame(r, UD2(0, CW - 70, 0, 4), UD2(0, CX, 0, 14), TH.C.RAISE, 0)
      track.Name = "Track_" .. key
      TH.corner(track)
      local fill = frame(track, UD2(0, 0, 1, 0), nil, TH.C.TEXT, 0)
      TH.corner(fill)
      local knob = frame(track, UD2(0, 10, 0, 18), UD2(0, 0, 0.5, -9), TH.C.TEXT, 0)
      TH.corner(knob)
      local val = text(r, "", UD2(0, 60, 0, 28), UD2(0, CX + CW - 60, 0, 2), TH.S.body, TH.C.TEXT, TH.F.mono, Enum.TextXAlignment.Right)
      val.Name = "Val_" .. key
      local hit = Instance.new("TextButton")
      hit.Name = "Hit_" .. key
      hit.Text, hit.BackgroundTransparency, hit.AutoButtonColor = "", 1, false
      hit.Size, hit.Position = UD2(0, CW - 56, 0, 28), UD2(0, CX - 7, 0, 2)
      hit.Parent = r
      local function refresh()
        local k = math.clamp((P[key] - it.lo) / (it.hi - it.lo), 0, 1)
        fill.Size = UD2(k, 0, 1, 0)
        knob.Position = UD2(k, -5, 0.5, -9)
        val.Text = it.fmt(P[key])
      end
      local function setFromX(x)
        local ap, as = track.AbsolutePosition, track.AbsoluteSize
        if as.X <= 1 then return end
        local k = math.clamp((x - ap.X) / as.X, 0, 1)
        local v = it.lo + (it.hi - it.lo) * k
        v = math.floor(v / it.step + 0.5) * it.step
        if math.abs(v - P[key]) > 1e-9 then
          P[key] = v
          refresh()
          changed()
        end
      end
      local drag = false
      hit.MouseButton1Down:Connect(function(x) drag = true setFromX(x) end)
      UIS.InputChanged:Connect(function(io)
        if drag and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then setFromX(io.Position.X) end
      end)
      UIS.InputEnded:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then drag = false end
      end)
      return refresh
    elseif it.kind == "check" then
      local b = Instance.new("TextButton")
      b.Name = "Check_" .. key
      b.Size, b.Position = UD2(0, 120, 0, 28), UD2(0, CX, 0, 2)
      b.BackgroundTransparency, b.AutoButtonColor, b.Text = 1, false, ""
      b.Parent = r
      local box = frame(b, UD2(0, 20, 0, 20), UD2(0, 0, 0, 4), TH.C.BG, 0.2)
      TH.corner(box)
      TH.stroke(box, true)
      local tick = frame(box, UD2(0, 10, 0, 10), UD2(0.5, -5, 0.5, -5), TH.C.BG, 0)   -- 勾上：白框里一个小实心方块
      local word = text(b, "", UD2(0, 80, 0, 28), UD2(0, 30, 0, 0), TH.S.body, TH.C.TEXT)
      b.MouseButton1Click:Connect(function()
        P[key] = not P[key]
        rows[key]()
        changed()
      end)
      return function()
        local on = P[key] == true
        box.BackgroundColor3, box.BackgroundTransparency = on and TH.C.TEXT or TH.C.BG, on and 0 or 0.2
        tick.Visible = on
        word.Text = on and L("是", "On") or L("否", "Off")
      end
    elseif it.kind == "drop" then
      local b = btn(r, "", UD2(0, CW, 0, 28), UD2(0, CX, 0, 2), TH.S.body)
      b.Name = "Drop_" .. key
      b.TextXAlignment = Enum.TextXAlignment.Left
      local pad = Instance.new("UIPadding")
      pad.PaddingLeft = UDim.new(0, 10)
      pad.Parent = b
      text(b, "▼", UD2(0, 20, 1, 0), UD2(1, -26, 0, 0), 9, TH.C.MUTE, TH.F.body, Enum.TextXAlignment.Center)
      local function label()
        for _, o in ipairs(it.opts) do if o[1] == P[key] then return o[2] end end
        return tostring(it.opts[1][2])
      end
      b.MouseButton1Click:Connect(function()
        if openDrop then openDrop:Destroy() openDrop = nil return end
        local list = frame(root, UD2(0, CW, 0, #it.opts * 30 + 6), UD2(0, b.AbsolutePosition.X / sc.Scale, 0, (b.AbsolutePosition.Y + b.AbsoluteSize.Y) / sc.Scale + 2), TH.C.PANEL, 0.02)
        list.Name = "DropList"
        list.ZIndex = 20
        TH.corner(list)
        TH.stroke(list, true)
        for i, o in ipairs(it.opts) do
          local ob = Instance.new("TextButton")
          ob.Name = "Opt_" .. i
          ob.Size, ob.Position = UD2(1, -6, 0, 28), UD2(0, 3, 0, 3 + (i - 1) * 30)
          ob.BackgroundColor3, ob.BackgroundTransparency, ob.BorderSizePixel = TH.C.TEXT, (o[1] == P[key]) and 0 or 1, 0
          ob.Text, ob.Font, ob.TextSize = "  " .. o[2], TH.F.body, TH.S.body
          ob.TextColor3 = (o[1] == P[key]) and TH.C.BG or TH.C.TEXT
          ob.TextXAlignment = Enum.TextXAlignment.Left
          ob.ZIndex = 21
          ob.Parent = list
          TH.corner(ob)
          ob.MouseButton1Click:Connect(function()
            P[key] = o[1]
            if openDrop then openDrop:Destroy() openDrop = nil end
            rows[key]()
            changed()
          end)
        end
        openDrop = list
      end)
      return function() b.Text = label() end
    elseif it.kind == "code" then
      r.Size = UD2(1, 0, 0, 120)
      local box = Instance.new("TextBox")
      box.Name = "CodeBox"
      box.Size, box.Position = UD2(0, CW - 110, 0, 32), UD2(0, CX, 0, 0)
      box.BackgroundColor3, box.BackgroundTransparency, box.BorderSizePixel = TH.C.BG, 0.1, 0
      box.Font, box.TextSize, box.TextColor3 = TH.F.mono, TH.S.sub, TH.C.TEXT
      box.PlaceholderText = L("输入兑换码", "Enter code")
      box.PlaceholderColor3 = TH.C.FAINT
      box.Text, box.ClearTextOnFocus = "", false
      box.TextXAlignment = Enum.TextXAlignment.Left
      box.Parent = r
      TH.corner(box)
      TH.stroke(box, true)
      local pad = Instance.new("UIPadding")
      pad.PaddingLeft = UDim.new(0, 10)
      pad.Parent = box
      local go = TH.button(r, L("兑换", "Redeem"), UD2(0, 100, 0, 32), UD2(0, CX + CW - 100, 0, 0))
      go.Name = "RedeemBtn"
      local res = text(r, "", UD2(0, CW + 120, 0, 20), UD2(0, CX, 0, 40), TH.S.body, TH.C.MUTE, TH.F.bold)
      res.Name = "RedeemRes"
      local n = text(r, L("活动、更新送的兑换码填在这里，不分大小写；兑换的东西直接进存档。", "Codes from events and updates (not case sensitive); rewards go straight to your profile."),
        UD2(0, CW + 120, 0, 34), UD2(0, CX, 0, 64), TH.S.small, TH.C.MUTE)
      n.TextWrapped, n.TextTruncate, n.TextYAlignment = true, Enum.TextTruncate.None, Enum.TextYAlignment.Top
      local function send()
        local c = box.Text
        if c == nil or string.gsub(c, "%s", "") == "" then
          res.Text, res.TextColor3 = L("先输入兑换码", "Enter a code first"), TH.C.WARN
          return
        end
        res.Text, res.TextColor3 = L("兑换中……", "Redeeming…"), TH.C.MUTE
        act("redeem", c)
      end
      go.MouseButton1Click:Connect(send)
      box.FocusLost:Connect(function(enter) if enter then send() end end)
      me:GetAttributeChangedSignal("Redeem"):Connect(function()
        local s = me:GetAttribute("Redeem")
        if type(s) ~= "string" then return end
        local st, n2 = string.match(s, "^(%a+)|(%d+)|")
        n2 = tonumber(n2) or 0
        if st == "ok" then
          res.Text, res.TextColor3 = L("兑换成功：解锁了 " .. n2 .. " 辆载具，去科技树里看", "Redeemed: " .. n2 .. " vehicles unlocked — check the tech tree"), TH.C.GOOD
          box.Text = ""
        elseif st == "none" then
          res.Text, res.TextColor3 = L("这个兑换码的东西你都已经有了", "You already have everything from this code"), TH.C.MUTE
        elseif st == "wait" then
          res.Text, res.TextColor3 = L("太快了，等两秒再试", "Too fast — wait two seconds"), TH.C.WARN
        else
          res.Text, res.TextColor3 = L("兑换码不对", "Invalid code"), TH.C.BAD
        end
      end)
      G.settingsRedeemBox = box   -- 测试用
      return function() end
    end
    return function() end
  end

  -- 每个分类一页（一开始就建好）；搜索时另建一页
  local pages = {}
  for _, c in ipairs(CATS) do
    local pg = frame(content, UD2(1, 0, 1, 0), nil, nil, 1)
    pg.Name = "Page_" .. c.key
    pg.Visible = false
    local y = 0
    for _, it in ipairs(ITEMS) do
      if it.cat == c.key then
        rows[it.key] = buildRow(pg, y, it)
        y += (it.kind == "code") and 128 or (it.note and 58 or 44)
      end
    end
    pages[c.key] = pg
  end
  local searchPg = frame(content, UD2(1, 0, 1, 0), nil, nil, 1)
  searchPg.Name = "Page_search"
  searchPg.Visible = false
  local searchRefresh = {}

  local function showCat(k)
    cur = k
    if openDrop then openDrop:Destroy() openDrop = nil end
    for kk, x in pairs(navBtns) do
      local on = kk == k
      x.b.BackgroundTransparency = on and 0.75 or 1
      x.bar.Visible = on
      x.t.TextColor3 = on and TH.C.TEXT or TH.C.MUTE
      x.t.Font = on and TH.F.bold or TH.F.body
    end
    for kk, p in pairs(pages) do p.Visible = (kk == k) and search.Text == "" end
    searchPg.Visible = search.Text ~= ""
  end
  for i, c in ipairs(CATS) do
    local b = Instance.new("TextButton")
    b.Name = "Nav_" .. c.key
    b.Size, b.Position = UD2(0, 236, 0, 32), UD2(0, 24, 0, 116 + (i - 1) * 34)
    b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = TH.C.RAISE, 1, 0
    b.AutoButtonColor, b.Text = false, ""
    b.Parent = root
    TH.corner(b)
    local bar = frame(b, UD2(0, 2, 1, -8), UD2(0, 0, 0, 4), TH.C.TEXT, 0)
    local t = text(b, L(c.zh, c.en), UD2(1, -24, 1, 0), UD2(0, 16, 0, 0), TH.S.body, TH.C.MUTE)
    navBtns[c.key] = { b = b, bar = bar, t = t }
    b.MouseButton1Click:Connect(function()
      if search.Text ~= "" then search.Text = "" end
      showCat(c.key)
    end)
  end
  -- 搜索：所有分类里名字对得上的项列在一页（前面小字写是哪个分类的）
  search:GetPropertyChangedSignal("Text"):Connect(function()
    for _, ch in ipairs(searchPg:GetChildren()) do ch:Destroy() end
    table.clear(searchRefresh)
    local q = string.lower(search.Text or "")
    if q ~= "" then
      local y = 0
      for _, it in ipairs(ITEMS) do
        if it.kind ~= "code" and (string.find(string.lower(it.zh), q, 1, true) or string.find(string.lower(it.en), q, 1, true)) then
          local f = buildRow(searchPg, y, it)
          table.insert(searchRefresh, f)
          f()
          y += it.note and 58 or 44
        end
      end
      if y == 0 then text(searchPg, L("没有找到", "No matches"), UD2(1, 0, 0, 24), UD2(0, 0, 0, 0), TH.S.body, TH.C.MUTE, TH.F.body, Enum.TextXAlignment.Center) end
    end
    showCat(cur)
  end)

  -- 右下：恢复默认（这一类的）、关闭（主按钮）
  local reset = btn(root, L("恢复默认", "Reset to default"), UD2(0, 150, 0, 36), UD2(1, -24 - 150 - 12 - 150, 1, -58))
  reset.Name = "Reset"
  local done = TH.button(root, L("关闭", "Close"), UD2(0, 150, 0, 36), UD2(1, -24 - 150, 1, -58), true)
  done.Name = "Done"
  reset.MouseButton1Click:Connect(function()
    local any = false
    for _, it in ipairs(ITEMS) do
      if it.cat == cur and DEF[it.key] ~= nil and P[it.key] ~= DEF[it.key] then
        P[it.key] = DEF[it.key]
        any = true
      end
    end
    for _, f in pairs(rows) do f() end
    if any then changed() end
  end)

  -- 开着设置时机库的界面先藏起来（同截图：背后只有模糊的 3D 机库），关了放回来
  local hid = {}
  local function hideOthers(on)
    if on then
      table.clear(hid)
      local pg = me:FindFirstChild("PlayerGui")
      for _, n in ipairs({ "TechHangar", "WtCam" }) do
        local g = pg and pg:FindFirstChild(n)
        if g and g:IsA("ScreenGui") and g.Enabled then g.Enabled = false table.insert(hid, g) end
      end
    else
      for _, g in ipairs(hid) do g.Enabled = true end
      table.clear(hid)
    end
  end
  local function close()
    if gui.Enabled then hideOthers(false) end
    gui.Enabled = false
    blurTo(false)
    if openDrop then openDrop:Destroy() openDrop = nil end
    if sendAt then sendAt = os.clock() end   -- 关的时候马上发（不用等 0.4 秒）
  end
  closeX.MouseButton1Click:Connect(close)
  back.MouseButton1Click:Connect(close)
  done.MouseButton1Click:Connect(close)
  UIS.InputBegan:Connect(function(io, gp)
    if gp then return end
    if gui.Enabled and io.KeyCode == Enum.KeyCode.Escape then close()
    elseif io.KeyCode == Enum.KeyCode.F10 then   -- 打仗的时候也能开（机库顶栏的齿轮是另一个入口）
      if gui.Enabled then close() elseif G.openSettings then G.openSettings() end
    end
  end)

  -- tab：兼容老入口（"ctl" / "gfx" / "snd" / "code"）
  local ALIAS = { gfx = "ground", ctl = "ctl", snd = "snd", code = "code", main = "main", ground = "ground", air = "air" }
  function G.openSettings(tab)
    readPrefs()
    for _, f in pairs(rows) do f() end
    search.Text = ""
    showCat(ALIAS[tab or ""] or cur)
    fit()
    if not gui.Enabled then hideOthers(true) end
    gui.Enabled = true
    blurTo(true)
  end
  G.closeSettings = close
  function G.settingsShown() return gui.Enabled end
  G.settingsGui = gui   -- 测试用
  me:GetAttributeChangedSignal("Prefs"):Connect(function()
    if sendAt then return end   -- 自己刚改的还没发出去：别被服务器回来的旧值盖掉
    readPrefs()
    for _, f in pairs(rows) do f() end
  end)
  showCat("main")
end

return Settings
