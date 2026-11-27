-- Roblox全面大战场——界面：部署（兵种卡片 + 地图上点出生点 + 出击）、战斗中的顶栏（时间、5 个据点）、血条、小地图、
--   击杀信息、屏幕中间的大字、底部提示、战况表（Tab）、结算画面、出错红条；所有文字按 G.lang 中英切换
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")

local UI = {}

function UI.init(G)
  local Config, Lang = G.Config, G.Lang
  local Map = require(RS:WaitForChild("Map"))
  local player = Players.LocalPlayer
  local RGB = Color3.fromRGB
  local function T(key, ...) return Lang.t(G.lang, key, ...) end
  G.T = T

  pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)   -- 武器栏自己画（中英文）
  pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)   -- 战况表自己画（Tab）

  local gui = Instance.new("ScreenGui")
  gui.Name = "Main"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.Parent = player:WaitForChild("PlayerGui")
  G.gui = gui

  ---------------------------------------------------------------- 小工具

  local TH = G.Theme   -- 统一外观（docs/style.md）
  local PANEL, LINE, TEXT, MUTE = TH.C.PANEL, TH.C.LINE, TH.C.TEXT, TH.C.MUTE
  local function frame(parent, size, pos, color, alpha, anchor)
    local f = Instance.new("Frame")
    f.Size = size
    f.Position = pos or UDim2.new()
    f.AnchorPoint = anchor or Vector2.new()
    f.BackgroundColor3 = color or PANEL
    f.BackgroundTransparency = alpha or 0.25
    f.BorderSizePixel = 0
    f.Parent = parent
    return f
  end
  local function round(f, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = f
    return f
  end
  local function stroke(f, color, t, alpha)
    local s = Instance.new("UIStroke")
    s.Color = color or LINE
    s.Thickness = t or 1
    s.Transparency = alpha or 0.85
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = f
    return s
  end
  local function label(parent, text, size, pos, ts, color, font, anchor, align)
    local l = Instance.new("TextLabel")
    l.Size = size
    l.Position = pos or UDim2.new()
    l.AnchorPoint = anchor or Vector2.new()
    l.BackgroundTransparency = 1
    l.Text = text or ""
    l.TextSize = ts or 16
    l.TextColor3 = color or TEXT
    l.Font = font or Enum.Font.BuilderSansMedium
    l.TextXAlignment = align or Enum.TextXAlignment.Center
    l.TextWrapped = true
    l.Parent = parent
    return l
  end
  local function button(parent, text, size, pos, color, anchor)
    local b = Instance.new("TextButton")
    b.Size = size
    b.Position = pos or UDim2.new()
    b.AnchorPoint = anchor or Vector2.new()
    b.BackgroundColor3 = color or RGB(40, 46, 52)
    b.BackgroundTransparency = 0.1
    b.BorderSizePixel = 0
    b.Text = text or ""
    b.TextColor3 = TEXT
    b.TextSize = 16
    b.Font = Enum.Font.BuilderSansBold
    b.AutoButtonColor = true
    b.Parent = parent
    round(b, 8)
    return b
  end
  -- 载具、飞机、舰艇、工事的信息面板（Drive / Fly / Sail / Gunner）跟新界面一个样子：深色、直角、细线；血条、装填条换成细线，名字不加粗
  local function flatPanel(p, o)
    for _, c in ipairs(p:GetChildren()) do if c:IsA("UICorner") then c:Destroy() end end
    p.BackgroundColor3, p.BackgroundTransparency = RGB(6, 8, 10), 0.2
    stroke(p, LINE, 1, 0.88)
    for _, bg in ipairs({ o.hp or false, o.rel or false }) do
      if bg then
        bg.Size = UDim2.new(bg.Size.X.Scale, bg.Size.X.Offset, 0, (bg == o.hp) and 3 or 2)
        bg.BackgroundColor3, bg.BackgroundTransparency = LINE, 0.86
      end
    end
    if o.name then o.name.Font, o.name.TextColor3 = Enum.Font.BuilderSansMedium, TEXT end
  end
  local function hpColor(k) return RGB(232, 84, 72):Lerp(TEXT, math.clamp(k, 0, 1)) end   -- 满血白、快没了红
  G.ui = { frame = frame, round = round, stroke = stroke, label = label, button = button, flatPanel = flatPanel, hpColor = hpColor }

  ---------------------------------------------------------------- 界面出现的短缓动（各模块共用）
  -- 用户 11-27「把各种动画效果做出丝滑感」：面板原来是 Visible 一下子开、一下子关。
  --   G.uiShow(界面, true)：马上显示，同时自己挂的 UIScale 从 0.96 弹到 1（0.18 秒，Quart Out）——只动比例、不动位置和透明度，
  --     别的代码照旧摆位置、改颜色，不打架；界面自己已经有 UIScale（手机缩放……）就不加，只显示。正在关（opt.out 缩到半路）又打开：从现在的大小回到 1
  --   G.uiShow(界面, false)：马上藏（按住看的、关窗口这些不拖泥带水）；opt.out = true 时先缩到 0.97（0.18 秒）再藏
  --   G.uiPop(界面, 从多大, 慢)：已经显示着的（命中结果、新的一行）从 1.07 之类缩回 1（0.12 秒）；慢 = true 时按打开面板的 0.18 秒 Quart Out。
  --     界面上有别人的 UIScale（WtTank 的 barScale 这种每帧写的）弹不了：返回 false、Studio 里提醒一次——这种改动 Position，或者外面包一层没有 UIScale 的框
  --   时长、缓动照 docs/style.md「动效」（workshop 的 Theme.T / Theme.EASE：界面上一律 Out、不用 In，退场 out 0.18、悬停 hover 0.12）：
  --     Theme.T 进了主分支就直接用它的数；按住 Tab 看的战况表比面板（panel 0.28）快，0.18
  --   系统打开「减少动态效果」（GuiService.ReducedMotionEnabled）就都不动。准星、命中标记、报错红字不用这个
  do
    local TweenService = game:GetService("TweenService")
    local GuiService = game:GetService("GuiService")
    local function reduced()
      local ok, v = pcall(function() return GuiService.ReducedMotionEnabled end)
      return ok and v == true
    end
    G.reducedMotion = reduced
    local TT = (TH and type(TH.T) == "table") and TH.T or {}
    local IN_T = TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    local OUT_T = TweenInfo.new(TT.out or 0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    local POP_T = TweenInfo.new(TT.hover or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local own = setmetatable({}, { __mode = "k" })   -- [界面] = { sc = 自己挂的 UIScale, tok = 第几次（关的动画结束时还是这一次才藏）}
    -- 界面上有没有别人的 UIScale（mine 是自己挂的那个）：每次都查——以后别的模块再给它加一个，两个 UIScale 会乘在一起
    local function foreign(obj, mine)
      for _, c in ipairs(obj:GetChildren()) do
        if c ~= mine and c:IsA("UIScale") then return true end
      end
      return false
    end
    local function scaleOf(obj)
      local e = own[obj]
      if e and e.sc and e.sc.Parent == obj then
        if not foreign(obj, e.sc) then return e end
        e.sc:Destroy()   -- 别人后来也挂了一个：让给它
        own[obj] = nil
        return nil
      end
      if foreign(obj, nil) then return nil end   -- 界面自己有 UIScale：不叠第二个
      local sc = Instance.new("UIScale")
      sc.Name = "EaseScale"
      sc.Parent = obj
      e = { sc = sc, tok = 0 }
      own[obj] = e
      return e
    end
    local warned = setmetatable({}, { __mode = "k" })
    local function cantScale(obj)
      if warned[obj] then return end
      warned[obj] = true
      local okS, studio = pcall(function() return game:GetService("RunService"):IsStudio() end)
      if okS and studio then warn("G.uiPop / uiShow：" .. obj:GetFullName() .. " 上有别的 UIScale，没法弹（改动 Position，或者外面包一层没有 UIScale 的框）") end
    end
    function G.uiShow(obj, on, opt)
      if not obj then return end
      local e = own[obj]
      if e then e.tok += 1 end   -- 关到一半的那次作废（不藏了）
      if on then
        local was = obj.Visible
        obj.Visible = true
        if was and not (opt and opt.again) then   -- 本来就开着：不重弹；关到一半（缩到 0.97 的路上）又打开：回到 1
          if e and e.sc.Parent == obj and e.sc.Scale ~= 1 then
            if reduced() then e.sc.Scale = 1 else TweenService:Create(e.sc, IN_T, { Scale = 1 }):Play() end
          end
          return
        end
        if reduced() then
          if e and e.sc.Parent then e.sc.Scale = 1 end
          return
        end
        e = scaleOf(obj)
        if not e then cantScale(obj) return end
        e.sc.Scale = (opt and opt.from) or 0.96
        TweenService:Create(e.sc, IN_T, { Scale = 1 }):Play()
      else
        if not obj.Visible then return end
        if not (opt and opt.out) or reduced() or not (e and e.sc.Parent) then
          obj.Visible = false
          if e and e.sc.Parent then e.sc.Scale = 1 end
          return
        end
        local tok = e.tok
        TweenService:Create(e.sc, OUT_T, { Scale = 0.97 }):Play()
        task.delay(OUT_T.Time, function()
          if e.tok ~= tok then return end   -- 中间又打开了
          obj.Visible = false
          e.sc.Scale = 1
        end)
      end
    end
    function G.uiPop(obj, from, slow)
      if not obj or reduced() then return false end
      local e = scaleOf(obj)
      if not e then cantScale(obj) return false end
      e.tok += 1
      e.sc.Scale = from or 1.07
      TweenService:Create(e.sc, slow and IN_T or POP_T, { Scale = 1 }):Play()
      return true
    end
    -- 镜头硬切的地方（机库出击进战场、退瞄准镜、收望远镜）盖一下黑再淡开：G.sceneFade(hold, fade, opt)
    --   · hold 秒全黑（把加载、阴影重画那一顿藏在黑里）。hold > 0 的到点以后还要等连着两帧顺（dt < 1/22，出生那一帧卡 200 毫秒别把黑和淡开的头几帧一起吃掉）、
    --     opt.ready() 给了也要它成立（比如出击：镜头真到了车上 G.drive / G.fly / G.sail），最多再等 opt.maxWait（默认 0.8）秒
    --   · 再 fade 秒淡开（Quad Out）；opt.from：从多黑开始（默认 0 全黑；来回切的退镜、收望远镜从半黑淡一下，不闪全黑）
    --   · 又来一次：上一次的补间停掉、从这一次接着（原来第二次只把黑设回去，上一次没跑完的补间下一帧又把它写回去）；
    --     上一次还盖着黑在等（出击等镜头到车上）：两边的条件都要满足、淡开取长的（半路一下退镜不把出击的黑冲掉）
    --   · 「减少动态效果」照样淡（淡入淡出就是它推荐用来替代运动的，DeathFx 也是这样），只是淡开不超过 0.15 秒
    --   盖在界面上面、不挡鼠标
    local fadeGui = Instance.new("ScreenGui")
    fadeGui.Name = "SceneFade"
    fadeGui.ResetOnSpawn = false
    fadeGui.IgnoreGuiInset = true
    fadeGui.DisplayOrder = 42   -- 阵亡黑幕（DeathFx 41）上面、性能面板（60）下面
    fadeGui.Enabled = false
    fadeGui.Parent = gui.Parent
    local fadeF = Instance.new("Frame")
    fadeF.Name = "Black"
    fadeF.Size = UDim2.fromScale(1, 1)
    fadeF.BackgroundColor3 = Color3.new(0, 0, 0)
    fadeF.BackgroundTransparency = 1
    fadeF.BorderSizePixel = 0
    fadeF.Active = false
    fadeF.Parent = fadeGui
    local fadeTok, fadeTw, pend = 0, nil, nil   -- pend：盖着黑、还没开始淡开的这一次
    local function startFade(p)
      pend = nil
      if fadeTw then fadeTw:Cancel() end
      fadeTw = TweenService:Create(fadeF, TweenInfo.new(p.fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
      fadeTw:Play()
      task.delay(p.fade, function()
        if fadeTok ~= p.tok then return end
        fadeTw = nil
        fadeGui.Enabled = false
        fadeF.BackgroundTransparency = 1
      end)
    end
    G.frameConn("SceneFade", function(dt)
      local p = pend
      if not p then return end
      local now = os.clock()
      if now < p.holdEnd then return end
      local ok = true
      if p.settle then
        if (dt or 0) < 1 / 22 then p.smooth += 1 else p.smooth = 0 end   -- 锁 30 帧的手机一帧 33 毫秒也算顺；出生卡的那一下几百毫秒
        ok = p.smooth >= 2
      end
      if ok and p.ready then
        local okR, r = pcall(p.ready)
        ok = (not okR) or r == true   -- ready 自己出错就不等了
      end
      if ok or now >= p.deadline then startFade(p) end
    end)
    function G.sceneFade(hold, fade, opt)
      fadeTok += 1
      if fadeTw then fadeTw:Cancel() fadeTw = nil end
      hold, fade = math.max(0, hold or 0.12), math.max(0.05, fade or 0.25)
      if reduced() then fade = math.min(fade, 0.15) end
      local from = math.clamp((opt and opt.from) or 0, 0, 0.95)
      if fadeGui.Enabled and fadeF.BackgroundTransparency < from then from = fadeF.BackgroundTransparency end   -- 还盖着更黑的（出击的黑没淡开）：别一下子变亮
      fadeF.BackgroundTransparency = from
      fadeGui.Enabled = true
      local settle = hold > 0
      if opt and opt.settle ~= nil then settle = opt.settle == true end
      local now = os.clock()
      local p = { tok = fadeTok, holdEnd = now + hold, fade = fade, settle = settle, smooth = 0, ready = opt and opt.ready }
      p.deadline = p.holdEnd + ((opt and opt.maxWait) or 0.8)
      local old = pend
      if old then
        p.holdEnd, p.deadline, p.fade = math.max(p.holdEnd, old.holdEnd), math.max(p.deadline, old.deadline), math.max(p.fade, old.fade)
        p.settle = p.settle or old.settle
        if old.ready then
          local r1, r2 = old.ready, p.ready
          p.ready = r2 and function() return r1() == true and r2() == true end or r1
        end
      end
      pend = p
    end
    G.sceneFadeState = function() return { on = fadeGui.Enabled, tr = fadeF.BackgroundTransparency, waiting = pend ~= nil } end   -- 测试用
  end

  local function teamColor(t)   -- 征服模式的中立据点（owner = "none"）：灰
    -- 队伍的颜色按看的人算：自己这一边绿、对面红、中立灰（统一外观 docs/style.md，不再攻方一律红、守方一律绿）
    if t ~= "atk" and t ~= "def" then return TH.C.NEUTRAL end
    return TH.side(t)
  end
  local function fmtTime(s)
    s = math.max(0, math.floor(s or 0))
    return string.format("%d:%02d", s // 60, s % 60)
  end

  ---------------------------------------------------------------- 出错红条、开服进度

  local errBar = label(gui, "", UDim2.new(1, -40, 0, 0), UDim2.new(0.5, 0, 0, 6), 14, RGB(255, 220, 220), Enum.Font.BuilderSansMedium, Vector2.new(0.5, 0))
  errBar.AutomaticSize = Enum.AutomaticSize.Y
  errBar.BackgroundColor3 = RGB(150, 30, 30)
  errBar.BackgroundTransparency = 0.15
  errBar.Visible = false
  errBar.ZIndex = 50
  local errs = {}
  function G.showError(msg)
    table.insert(errs, 1, tostring(msg))
    while #errs > 3 do table.remove(errs) end
    errBar.Text = table.concat(errs, "\n")
    errBar.Visible = true
  end

  local loading = frame(gui, UDim2.fromScale(1, 1), nil, RGB(10, 14, 18), 0)
  loading.ZIndex = 40
  local loadText = label(loading, "", UDim2.new(1, 0, 0, 40), UDim2.fromScale(0, 0.5), 22, TEXT, Enum.Font.BuilderSansBold)
  loadText.ZIndex = 41

  ---------------------------------------------------------------- 部署界面
  -- 照用户给的参考图：不选兵种，进来默认就是一个士兵；底下一排装备格改枪械配置（点一格，上面弹出能换的），右下白色「选择生成点」→ 地图上选点、出击。
  --   两页：kit 装备（左上标题、说明、数据条，右边转着的大图，底下 4 格）· spawn 生成点（左边出生点列表，右边地图）
  --   要比参考图精致、简洁（用户：现在这个太卡通）：黑底半透明、细线、直角、小字，只有主按钮是白底黑字
  local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled   -- G.mobile 要到 Play.lua 才有：这里自己判断
  local M0 = mobile and 18 or 48   -- 左右边距
  local WHITE, DIM, FAINT = Color3.new(1, 1, 1), TH.C.MUTE, TH.C.FAINT
  local deploy = frame(gui, UDim2.fromScale(1, 1), nil, RGB(4, 6, 8), 0.08)
  deploy.Name = "Deploy"
  deploy.Visible = false
  deploy.ZIndex = 10
  do   -- 保留远景，限制夜视和照明弹在部署页背后的亮斑
    local g = Instance.new("UIGradient")
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.13), NumberSequenceKeypoint.new(1, 0.24) })
    g.Rotation = -20
    g.Parent = deploy
  end
  local function hair(parent, size, pos, alpha, anchor)   -- 一像素的细线
    return frame(parent, size, pos, WHITE, alpha or 0.86, anchor)
  end
  local function txt(parent, s, size, pos, ts, color, font, anchor, align)
    local l = label(parent, s, size, pos, ts, color, font, anchor, align)
    l.TextWrapped = false
    l.TextTruncate = Enum.TextTruncate.AtEnd
    return l
  end
  -- 主按钮：白底黑字（字写在按钮自己身上），右边一个小键位
  local function mainButton(parent, size, pos, anchor)
    local b = Instance.new("TextButton")
    b.Size, b.Position, b.AnchorPoint = size, pos, anchor or Vector2.new()
    b.BackgroundColor3 = WHITE
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Text = ""
    b.TextSize = mobile and 16 or 19
    b.TextColor3 = RGB(10, 10, 12)
    b.Font = Enum.Font.BuilderSansBold
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Parent = parent
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 22)
    pad.Parent = b
    local k = txt(b, "", UDim2.fromOffset(60, 20), UDim2.new(1, -18, 0.5, 0), 11, RGB(120, 120, 124), Enum.Font.BuilderSansMedium, Vector2.new(1, 0.5), Enum.TextXAlignment.Right)
    return b, b, k
  end
  -- 只有字的按钮（页签、换阵营、语言）
  local function link(parent, s, size, pos, ts, anchor, align)
    local b = Instance.new("TextButton")
    b.Size, b.Position, b.AnchorPoint = size, pos, anchor or Vector2.new()
    b.BackgroundTransparency = 1
    b.Text = s
    b.TextSize = ts or 13
    b.TextColor3 = DIM
    b.Font = Enum.Font.BuilderSansMedium
    b.TextXAlignment = align or Enum.TextXAlignment.Left
    b.AutoButtonColor = false
    b.Parent = parent
    return b
  end

  local sel = { role = nil, spawn = nil, page = nil, pageUser = nil, slot = nil }
  G.deploySel = sel
  -- 装备栏：上次选的（这一局里记着）；开局默认 M4 + 急救包 + 手雷
  sel.kit = table.clone(Config.LoadoutDefault or { primary = "m4" })
  local SLOTS = Config.Loadout or { { id = "primary", opts = { "m4" } } }
  -- R 币解锁（Config.Passes）：服务器把有没有写在玩家属性 Pass_<名字> 上；通行证编号还是 0 的谁都能用
  local function passOk(name)
    local c = Config.Passes and Config.Passes[name]
    if not c or (c.id or 0) == 0 then return true end
    return player:GetAttribute("Pass_" .. name) == true
  end
  G.passOk = passOk
  G.passFor = function(item) return Config.PassFor and Config.PassFor[item] end   -- 物品 / 机型 → 通行证名（不用的是 nil）
  G.buyPass = function(name) pcall(function() G.R.Act:FireServer("buyPass", name) end) end
  for name in pairs(Config.Passes or {}) do
    pcall(function() player:GetAttributeChangedSignal("Pass_" .. name):Connect(function() if G.refreshDeploy then G.refreshDeploy() end end) end)
  end

  -- 顶上一行：页签（装备 / 生成点），右边换阵营、语言
  local topY = mobile and 74 or 96
  local tabs = {}
  for i, pg in ipairs({ "kit", "spawn" }) do
    local b = link(deploy, "", UDim2.fromOffset(mobile and 70 or 92, 26), UDim2.fromOffset(M0 + (i - 1) * (mobile and 80 or 104), topY), mobile and 14 or 16)
    b.Font = Enum.Font.BuilderSansBold
    local u = hair(b, UDim2.new(0, 22, 0, 2), UDim2.new(0, 0, 1, 2), 0)
    tabs[pg] = { b = b, u = u }
  end
  local langBtn = link(deploy, "", UDim2.fromOffset(110, 26), UDim2.new(1, -M0, 0, topY), 12, Vector2.new(1, 0), Enum.TextXAlignment.Right)
  local sideBtn = link(deploy, "", UDim2.fromOffset(110, 26), UDim2.new(1, -M0 - 118, 0, topY), 12, Vector2.new(1, 0), Enum.TextXAlignment.Right)
  sideBtn.Activated:Connect(function() if G.showFaction then G.showFaction() end end)
  sideBtn.Visible = false   -- 用户 11-22：「界面就不要写 switch side 了」——自动分队，不再从部署界面换阵营
  local menuBtn = link(deploy, "", UDim2.fromOffset(80, 26), UDim2.new(1, -M0 - 236, 0, topY), 12, Vector2.new(1, 0), Enum.TextXAlignment.Right)
  menuBtn.Activated:Connect(function() if G.showMenu then G.showMenu() end end)
  hair(deploy, UDim2.new(1, -M0 * 2, 0, 1), UDim2.fromOffset(M0, topY + 34), 0.9)

  local kitPage = frame(deploy, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)
  local spawnPage = frame(deploy, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)

  ------------------------------------ 装备页
  local infoY = topY + (mobile and 40 or 66)
  local facDot = frame(kitPage, UDim2.fromOffset(6, 6), UDim2.fromOffset(M0, infoY + 5), WHITE, 0)
  local facLine = txt(kitPage, "", UDim2.fromOffset(360, 16), UDim2.fromOffset(M0 + 14, infoY), 12, DIM, Enum.Font.BuilderSansMedium, nil, Enum.TextXAlignment.Left)
  local bigName = txt(kitPage, "", UDim2.fromOffset(mobile and 360 or 520, mobile and 34 or 50), UDim2.fromOffset(M0 - 2, infoY + 20), mobile and 28 or 42, WHITE, Enum.Font.BuilderSansBold, nil, Enum.TextXAlignment.Left)
  local bigDesc = txt(kitPage, "", UDim2.fromOffset(mobile and 360 or 460, 18), UDim2.fromOffset(M0, infoY + (mobile and 56 or 76)), 13, DIM, Enum.Font.BuilderSansMedium, nil, Enum.TextXAlignment.Left)
  local stats = {}
  for k = 1, 4 do
    local y = infoY + (mobile and 84 or 112) + (k - 1) * 24
    local a = txt(kitPage, "", UDim2.fromOffset(80, 16), UDim2.fromOffset(M0, y), 11, DIM, Enum.Font.BuilderSansMedium, nil, Enum.TextXAlignment.Left)
    local bg = hair(kitPage, UDim2.fromOffset(180, 2), UDim2.fromOffset(M0 + 86, y + 7), 0.86)
    local fill = frame(bg, UDim2.fromScale(0.5, 1), nil, WHITE, 0.05)
    local v = txt(kitPage, "", UDim2.fromOffset(84, 16), UDim2.fromOffset(M0 + 274, y), 11, WHITE, Enum.Font.BuilderSansMedium, nil, Enum.TextXAlignment.Left)
    stats[k] = { a = a, bg = bg, fill = fill, v = v }
    a.Visible, bg.Visible, v.Visible = not mobile, not mobile, not mobile
  end
  -- 改枪（用户 11-20：对标三角洲行动，Gunsmith.lua）：主武器那格下面一个「改枪」按钮，旁边一行现在装的配件
  local GMods = require(game:GetService("ReplicatedStorage"):WaitForChild("GunMods"))
  local gsY = infoY + (mobile and 84 or 112 + 4 * 24 + 6)
  local gsBtn = Instance.new("TextButton")
  gsBtn.Size, gsBtn.Position = UDim2.fromOffset(mobile and 110 or 132, mobile and 30 or 34), UDim2.fromOffset(M0, gsY)
  gsBtn.BackgroundColor3, gsBtn.BackgroundTransparency, gsBtn.BorderSizePixel, gsBtn.AutoButtonColor = RGB(206, 255, 72), 0, 0, true
  gsBtn.Font, gsBtn.TextSize, gsBtn.TextColor3, gsBtn.Text = Enum.Font.BuilderSansExtraBold, mobile and 13 or 14, RGB(18, 22, 8), ""
  gsBtn.Visible = false
  gsBtn.Parent = kitPage
  local gsLine = txt(kitPage, "", UDim2.fromOffset(mobile and 230 or 340, 16), UDim2.fromOffset(M0 + (mobile and 120 or 144), gsY + (mobile and 7 or 9)), 11, DIM, Enum.Font.BuilderSansMedium, nil, Enum.TextXAlignment.Left)
  gsLine.Visible = false
  local gsLv = txt(kitPage, "", UDim2.fromOffset(120, 14), UDim2.fromOffset(M0, gsY + (mobile and 34 or 40)), 10, FAINT, Enum.Font.BuilderSansBold, nil, Enum.TextXAlignment.Left)
  gsLv.Visible = false

  gsBtn.Activated:Connect(function()
    if sel.gsId and G.openGunsmith then
      G.openGunsmith(sel.gsId, function() if G.refreshDeploy then G.refreshDeploy() end end)
    end
  end)
  -- 服务器改好了配件 / 加了枪械经验（玩家属性）：部署界面开着就刷新
  for _, a in ipairs({ "Gun_m4", "Gun_sniper", "GunXp_m4", "GunXp_sniper" }) do
    pcall(function() player:GetAttributeChangedSignal(a):Connect(function() if deploy.Visible and G.refreshDeploy then G.refreshDeploy() end end) end)
  end

  -- 右边的大图（慢慢左右转）
  local big = Instance.new("ViewportFrame")
  big.Name = "GearBig"
  big.BackgroundTransparency = 1
  big.Size = mobile and UDim2.new(0.5, 0, 0.42, 0) or UDim2.new(0.56, 0, 0.5, 0)
  big.Position = mobile and UDim2.new(0.97, 0, 0.16, 0) or UDim2.new(0.97, 0, 0.17, 0)
  big.AnchorPoint = Vector2.new(1, 0)
  big.Ambient = RGB(150, 152, 158)
  big.LightColor = RGB(255, 250, 242)
  big.LightDirection = Vector3.new(-0.35, -1, -0.55)
  big.Parent = kitPage
  -- 底下的装备格
  local SW, SH, GAP = mobile and 128 or 206, mobile and 80 or 124, mobile and 6 or 10
  local slotY = mobile and -14 or -40
  local cards = {}
  local picker = frame(kitPage, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)
  picker.Visible = false
  local pickHead = txt(picker, "", UDim2.fromOffset(300, 16), UDim2.new(0, M0, 1, slotY - SH - 14 - (mobile and 70 or 104) - 22), 12, DIM, Enum.Font.BuilderSansBold, nil, Enum.TextXAlignment.Left)
  local pickCards = {}
  local function newCard(parent, w, h)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w, h)
    b.BackgroundColor3 = RGB(12, 14, 16)
    b.BackgroundTransparency = 0.35
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Text = ""
    b.Parent = parent
    local st = Instance.new("UIStroke")
    st.Color = WHITE
    st.Thickness = 1
    st.Transparency = 0.88
    st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    st.Parent = b
    local vp = Instance.new("ViewportFrame")
    vp.BackgroundTransparency = 1
    vp.Size = UDim2.new(1, -24, 1, -(mobile and 34 or 44))
    vp.Position = UDim2.fromOffset(12, mobile and 10 or 16)
    vp.Ambient = RGB(150, 152, 158)
    vp.LightColor = RGB(255, 250, 242)
    vp.LightDirection = Vector3.new(-0.35, -1, -0.55)
    vp.Parent = b
    local idx = txt(b, "", UDim2.fromOffset(40, 14), UDim2.fromOffset(10, 7), 10, FAINT, Enum.Font.BuilderSansBold, nil, Enum.TextXAlignment.Left)
    local cat = txt(b, "", UDim2.fromOffset(w - 50, 14), UDim2.new(1, -10, 0, 7), 10, FAINT, Enum.Font.BuilderSansMedium, Vector2.new(1, 0), Enum.TextXAlignment.Right)
    local nm = txt(b, "", UDim2.new(1, -60, 0, 16), UDim2.new(0, 10, 1, -(mobile and 20 or 24)), mobile and 11 or 13, WHITE, Enum.Font.BuilderSansBold, nil, Enum.TextXAlignment.Left)
    local cnt = txt(b, "", UDim2.fromOffset(50, 18), UDim2.new(1, -10, 1, -(mobile and 21 or 26)), mobile and 13 or 16, WHITE, Enum.Font.BuilderSansBold, Vector2.new(1, 0), Enum.TextXAlignment.Right)
    local bar = frame(b, UDim2.new(1, 0, 0, 2), nil, WHITE, 1)   -- 选中的那格顶上一道白线
    return { b = b, st = st, vp = vp, idx = idx, cat = cat, nm = nm, cnt = cnt, bar = bar, item = nil, wait = false }
  end
  for i, slot in ipairs(SLOTS) do
    local c = newCard(kitPage, SW, SH)
    c.b.AnchorPoint = Vector2.new(0, 1)
    c.b.Position = UDim2.new(0, M0 + (i - 1) * (SW + GAP), 1, slotY)
    c.slot = slot
    cards[i] = c
  end
  -- 兵种（用户 11-24：「各种角色配备各种武器」）：装备栏上面一排，点一个整套换成这个兵种的（Config.RoleKits；之后每格照样能改）；
  --   选格子（上面弹出可选的）时藏起来不挡
  local roleRow = Instance.new("ScrollingFrame")
  roleRow.Name = "RoleRow"
  roleRow.Size = UDim2.new(1, -M0 * 2, 0, mobile and 24 or 28)
  roleRow.Position = UDim2.new(0, M0, 1, slotY - SH - 12)
  roleRow.AnchorPoint = Vector2.new(0, 1)
  roleRow.BackgroundTransparency, roleRow.BorderSizePixel = 1, 0
  roleRow.ScrollBarThickness = 0
  roleRow.ScrollingDirection = Enum.ScrollingDirection.X
  roleRow.AutomaticCanvasSize = Enum.AutomaticSize.X
  roleRow.CanvasSize = UDim2.new()
  roleRow.Parent = kitPage
  local roleLay = Instance.new("UIListLayout")
  roleLay.FillDirection = Enum.FillDirection.Horizontal
  roleLay.Padding = UDim.new(0, mobile and 10 or 16)
  roleLay.SortOrder = Enum.SortOrder.LayoutOrder
  roleLay.VerticalAlignment = Enum.VerticalAlignment.Center
  roleLay.Parent = roleRow
  local roleHead = txt(roleRow, "", UDim2.fromOffset(mobile and 34 or 44, 16), nil, 11, FAINT, Enum.Font.BuilderSansBold, nil, Enum.TextXAlignment.Left)
  roleHead.LayoutOrder = 0
  local roleBtns = {}
  for i, r in ipairs(Config.RoleKits or {}) do
    local b = link(roleRow, "", UDim2.fromOffset(mobile and 52 or 66, mobile and 22 or 26), UDim2.new(), mobile and 11 or 13, nil, Enum.TextXAlignment.Center)
    b.Name = "Role_" .. r.id
    b.LayoutOrder = i
    local u = hair(b, UDim2.new(0, 18, 0, 2), UDim2.new(0.5, -9, 1, -2), 1)
    b.Activated:Connect(function()
      local k = Config.roleKit and Config.roleKit(r.id, (G.S and G.S.team) or "atk")
      if not k then return end
      sel.kit = k
      sel.kitRole = r.id
      sel.slot = nil
      G.refreshDeploy()
    end)
    roleBtns[r.id] = { b = b, u = u }
  end
  -- 主按钮：选择生成点
  local CW, CH = mobile and 200 or 270, mobile and 48 or 62
  local goSpawn, goSpawnT, goSpawnK = mainButton(kitPage, UDim2.fromOffset(CW, CH), UDim2.new(1, -M0, 1, slotY), Vector2.new(1, 1))
  local phaseText = txt(deploy, "", UDim2.fromOffset(360, 16), UDim2.new(1, -M0, 1, slotY - CH - 12), 12, DIM, Enum.Font.BuilderSansMedium, Vector2.new(1, 1), Enum.TextXAlignment.Right)

  -- 数量（消耗品：弹匣 + 备弹）
  local function countOf(id)
    local w = Config.Weapons[id]
    if not w or w.kind == "gun" or w.kind == "heal" or w.kind == "repair" or w.kind == "breach" or w.kind == "spot" then return nil end
    return (w.mag or 1) + (w.reserve or 0)
  end
  -- 数据条：枪看伤害 / 射速 / 射程 / 精度；炸的看伤害 / 杀伤半径 / 射程 / 弹药；工具不显示
  local function statRows(id)
    local w = (G.W and G.W[id]) or Config.Weapons[id]   -- 枪按装的配件算（改枪；GunKit.lua）
    if not w then return {} end
    local m = function(studs) return math.floor((studs or 0) / 2.8 + 0.5) end
    if w.kind == "gun" then
      return {
        { T("deploy.stat.dmg"), math.clamp(w.dmg / 100, 0, 1), tostring(w.dmg) },
        { T("deploy.stat.rate"), math.clamp((60 / w.rate) / 800, 0, 1), T("deploy.rpm", math.floor(60 / w.rate + 0.5)) },
        { T("deploy.stat.range"), math.clamp(m(w.range) / 550, 0, 1), T("deploy.m", m(w.range)) },
        { T("deploy.stat.acc"), math.clamp(1 - (w.spread or 0) * (w.adsK or 1) / 0.8, 0.05, 1), string.format("±%.2f°", (w.spread or 0) * (w.adsK or 1)) },   -- 开镜的精度（spread 是腰射）
      }
    elseif w.dmg then
      local rows = {
        { T("deploy.stat.dmg"), math.clamp(w.dmg / 260, 0, 1), tostring(w.dmg) },
        { T("deploy.stat.blast"), math.clamp((w.splash or 0) / 20, 0, 1), T("deploy.m", m(w.splash)) },
      }
      if w.range or w.maxR then table.insert(rows, { T("deploy.stat.range"), math.clamp(m(w.range or w.maxR) / 500, 0, 1), T("deploy.m", m(w.range or w.maxR)) }) end
      local n = countOf(id)
      if n then table.insert(rows, { T("deploy.stat.ammo"), math.clamp(n / 12, 0, 1), "×" .. n }) end
      return rows
    end
    return {}
  end

  local focus = 1   -- 大图、标题看的是哪一格
  local bigItem, bigWait = nil, false
  -- 各兵种的枪两边是不同的制式（GearDefs.BY）：有「weapon.<枪>.<阵营>」的按自己这边的写（机枪：QJY-88 / M249）
  local function itemName(id)
    if not id then return T("deploy.none") end
    local team = (G.S and G.S.team) or "atk"
    local k2 = "weapon." .. id .. "." .. team
    local v = T(k2)
    if v ~= k2 then return v end
    return T("weapon." .. id)
  end
  local function setModel(vp, id, team)
    if not G.gearModel or not G.viewFit then return id ~= nil end   -- GearView 还没起来：等一会儿再画
    if not id then
      G.viewFit(vp, nil)
      return false
    end
    local m, wait, real
    if G.gunModel and GMods.has(id) and G.myBuild then   -- 改枪：装着现在这一套配件的枪
      m, wait = G.gunModel(id, team, G.myBuild(id))
      real = m ~= nil
      if not m then m, wait, real = G.gearModel(id, team) end
    else
      m, wait, real = G.gearModel(id, team)
    end
    if m and not real then   -- 零件拼的方块不放（粗糙）：等真模型
      m:Destroy()
      m = nil
    end
    G.viewFit(vp, m, 1.12)
    return wait
  end

  ------------------------------------ 生成点页
  local listW = mobile and 230 or 340
  local listY = topY + (mobile and 40 or 66)
  local listHead = txt(spawnPage, "", UDim2.fromOffset(listW, 16), UDim2.fromOffset(M0, listY), 12, DIM, Enum.Font.BuilderSansBold, nil, Enum.TextXAlignment.Left)
  local list = Instance.new("ScrollingFrame")
  list.Size = UDim2.new(0, listW, 1, -(listY + 24) - (mobile and 80 or 150))
  list.Position = UDim2.fromOffset(M0, listY + 24)
  list.BackgroundTransparency = 1
  list.BorderSizePixel = 0
  list.ScrollBarThickness = 2
  list.ScrollBarImageColor3 = WHITE
  list.CanvasSize = UDim2.new()
  list.AutomaticCanvasSize = Enum.AutomaticSize.Y
  list.Parent = spawnPage
  local listLayout = Instance.new("UIListLayout")
  listLayout.Padding = UDim.new(0, 4)
  listLayout.SortOrder = Enum.SortOrder.LayoutOrder
  listLayout.Parent = list
  -- 地图：右边一个正方形
  local mapBox = frame(spawnPage, mobile and UDim2.new(1, -(M0 * 2 + listW + 16), 1, -(listY + 80)) or UDim2.new(1, -(M0 * 2 + listW + 40), 1, -(listY + 150)),
    UDim2.new(1, -M0, 0, listY), RGB(0, 0, 0), 1, Vector2.new(1, 0))
  local mapHolder = frame(mapBox, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0), RGB(0, 0, 0), 1, Vector2.new(0.5, 0))
  local aspect = Instance.new("UIAspectRatioConstraint")
  aspect.AspectRatio = 1
  aspect.Parent = mapHolder
  local spawnLayer = nil
  local spawnBtns = {}
  -- 装备一行 + 改装备
  local kitLine = txt(spawnPage, "", UDim2.fromOffset(mobile and 300 or 520, 16), UDim2.new(0, M0, 1, slotY - 44), 12, DIM, Enum.Font.BuilderSansMedium, nil, Enum.TextXAlignment.Left)
  local editKit = link(spawnPage, "", UDim2.fromOffset(160, 18), UDim2.new(0, M0, 1, slotY), 12, Vector2.new(0, 1))
  editKit.TextColor3 = WHITE
  editKit.Font = Enum.Font.BuilderSansBold
  -- 主按钮：出击
  local deployBtn, deployBtnT, deployBtnK = mainButton(spawnPage, UDim2.fromOffset(CW, CH), UDim2.new(1, -M0, 1, slotY), Vector2.new(1, 1))

  -- 键位说明放在部署界面最下面（战斗里第一人称不显示键位）
  local deployHelp = label(deploy, "", UDim2.new(1, -40, 0, 14), UDim2.new(0.5, 0, 1, -16), 11, FAINT, Enum.Font.BuilderSans, Vector2.new(0.5, 0))
  deployHelp.Visible = not G.mobile
  -- 开着菜单（挂载编辑器、部署界面）：鼠标要放出来点东西
  function G.menuOpen()
    return (G.hangarOpen ~= nil and G.hangarOpen()) or (G.pickerOpen ~= nil and G.pickerOpen()) or deploy.Visible
      or (G.tacOpen ~= nil and G.tacOpen())   -- 战术平板开着：鼠标放出来点地图、不开枪
      or (G.gunsmithOpen ~= nil and G.gunsmithOpen())   -- 改枪界面
      or (G.garageOpen ~= nil and G.garageOpen())   -- 坦克改装界面（用户 11-21：鼠标不显示——没算进来，步行第一人称时 stepUI 把鼠标图标藏了）
  end

  local function doDeploy()
    local S = G.S
    if not S or S.alive or (S.wait or 0) > 0 then return end
    if not sel.spawn then G.toast(T("ui.needPick"), "bad") return end
    G.R.Act:FireServer("deploy", sel.role or sel.kit, sel.spawn)
  end
  deployBtn.Activated:Connect(doDeploy)
  local function setPage(pg, user)
    sel.page = pg
    if user then sel.pageUser = pg end
    sel.slot = nil
    G.refreshDeploy()
  end
  goSpawn.Activated:Connect(function() setPage("spawn", true) end)
  editKit.Activated:Connect(function() setPage("kit", true) end)
  tabs.kit.b.Activated:Connect(function() setPage("kit", true) end)
  tabs.spawn.b.Activated:Connect(function() setPage("spawn", true) end)
  -- 回车：装备页 → 生成点 → 出击；退格：回装备页
  UIS.InputBegan:Connect(function(io, gp)
    if gp or not deploy.Visible then return end
    if io.KeyCode == Enum.KeyCode.Return then
      if sel.page == "spawn" then doDeploy() else setPage("spawn", true) end
    elseif io.KeyCode == Enum.KeyCode.Backspace and sel.page == "spawn" then
      setPage("kit", true)
    end
  end)

  local function spawnName(s)
    if s.kind == "beach" then return T("beach." .. s.beach) end
    if s.kind == "point" then return T("point." .. s.point) end
    if s.kind == "rally" then return T("spawn.rally", T("point." .. s.point)) end   -- 守方前线集结点（据点后方）
    if s.kind == "staging" then return T("spawn.staging", T("point." .. s.point)) end   -- 攻方攻击出发阵地（据点前面）
    if s.kind == "camp" then return T("spawn.camp") end
    if s.kind == "afield" then return T("spawn.afield") end
    if s.kind == "fleet" then return T("spawn.fleet") end
    if s.kind == "para" then return T("spawn.para") end
    if s.kind == "cv" then return T("spawn.cv") end
    if s.kind == "barge" then return T("spawn.barge") end
    if s.kind == "af2" then return T("spawn.af2") end
    if s.kind == "af3" then return T("spawn.af3") end   -- 沙海：守方主基地的机场
    if s.kind == "redbase" then return T("spawn.redbase") end   -- 沙漠图：红方前进基地
    if s.kind == "squad" then return T("spawn.squad", s.name or "?") end   -- 小队队友身边（Squads.lua）
    return s.id
  end

  -- 推荐的出生点（服务器标 rec：离当前目标最近的）：没选过、选的不能用了、换了阶段 / 新一局，就自动选上它——进来按一下出击就上战场
  local function autoSpawn(S)
    local ids, rec = {}, nil
    for _, s in ipairs(S.spawns or {}) do
      ids[s.id] = s
      if s.rec then rec = s end
    end
    local cur = sel.spawn and ids[sel.spawn]
    local stale = not cur or not cur.ok or sel.spawnStage ~= (S.stage or 1) or sel.spawnRound ~= S.round
    if stale and rec then
      sel.spawn = rec.id
      sel.spawnStage, sel.spawnRound = S.stage or 1, S.round
    end
  end
  -- 出生点：左边一列（名字、能不能去），地图上一个个小点
  local function buildSpawns(S)
    for _, b in ipairs(spawnBtns) do b:Destroy() end
    spawnBtns = {}
    local ids = {}
    for i, s in ipairs(S.spawns or {}) do
      ids[s.id] = s
      local chosen = sel.spawn == s.id
      local function pick()
        if not s.ok then G.toast(T("ui.spawnBlocked"), "bad") return end
        sel.spawn = s.id
        sel.spawnStage, sel.spawnRound = S.stage or 1, S.round   -- 自己挑的：这一阶段里一直用它
        G.refreshDeploy()
      end
      -- 列表里一行
      local row = Instance.new("TextButton")
      row.LayoutOrder = i
      row.Size = UDim2.new(1, -6, 0, mobile and 30 or 38)
      row.BackgroundColor3 = chosen and RGB(255, 255, 255) or RGB(12, 14, 16)
      row.BackgroundTransparency = chosen and 0.9 or 0.45
      row.BorderSizePixel = 0
      row.AutoButtonColor = false
      row.Text = ""
      row.Parent = list
      frame(row, UDim2.new(0, 2, 1, 0), nil, WHITE, chosen and 0 or 1)
      txt(row, spawnName(s), UDim2.new(1, -110, 1, 0), UDim2.fromOffset(14, 0), mobile and 12 or 14, s.ok and WHITE or FAINT, chosen and Enum.Font.BuilderSansBold or Enum.Font.BuilderSansMedium, nil, Enum.TextXAlignment.Left)
      local tag = txt(row, s.ok and (s.rec and T("deploy.rec") or "") or T("deploy.blocked"), UDim2.fromOffset(90, 16), UDim2.new(1, -12, 0.5, 0), 11, FAINT, Enum.Font.BuilderSansBold, Vector2.new(1, 0.5), Enum.TextXAlignment.Right)
      if s.ok and s.rec then tag.TextColor3 = teamColor(S.team or "atk"):Lerp(WHITE, 0.3) end   -- 推荐：离当前目标最近
      row.Activated:Connect(pick)
      table.insert(spawnBtns, row)
      -- 地图上的点
      if s.x and spawnLayer then
        local u, v = G.mapUV(s.x, s.z)
        local b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(0.5, 0.5)
        b.Position = UDim2.fromScale(u, v)
        b.Size = UDim2.fromOffset(chosen and 16 or 11, chosen and 16 or 11)
        b.Rotation = 45
        b.BackgroundColor3 = s.ok and WHITE or RGB(110, 110, 110)
        b.BackgroundTransparency = chosen and 0 or 0.25
        b.BorderSizePixel = 0
        b.Text = ""
        b.ZIndex = 8
        b.Parent = spawnLayer
        local st = Instance.new("UIStroke")
        st.Color = RGB(0, 0, 0)
        st.Thickness = 1
        st.Transparency = 0.3
        st.Parent = b
        if chosen then
          local tip = label(spawnLayer, spawnName(s), UDim2.fromOffset(160, 16), UDim2.new(u, 0, v, 12), 12, WHITE, Enum.Font.BuilderSansBold, Vector2.new(0.5, 0))
          tip.ZIndex = 8
          tip.TextStrokeTransparency = 0.4
          table.insert(spawnBtns, tip)
        end
        b.Activated:Connect(pick)
        table.insert(spawnBtns, b)
      end
    end
    if sel.spawn and (not ids[sel.spawn] or not ids[sel.spawn].ok) then sel.spawn = nil end
  end

  -- 装备格：上面弹出这一格能换的
  local function openPicker(i)
    for _, c in ipairs(pickCards) do c.b:Destroy() end
    pickCards = {}
    if sel.slot == i or not SLOTS[i] then sel.slot = nil picker.Visible = false return end
    sel.slot = i
    focus = i
    local slot = SLOTS[i]
    local opts = table.clone(slot.opts)
    if slot.none then table.insert(opts, false) end
    local S = G.S or {}
    local pw, ph = mobile and 112 or 168, mobile and 70 or 104
    local x0 = math.max(M0, M0 + (i - 1) * (SW + GAP))
    pickHead.Text = T("deploy.choose", T("deploy.slot." .. slot.id))
    pickHead.Position = UDim2.new(0, x0, 1, slotY - SH - 14 - ph - 22)
    for k, id in ipairs(opts) do
      local c = newCard(picker, pw, ph)
      c.b.AnchorPoint = Vector2.new(0, 1)
      c.b.Position = UDim2.new(0, x0 + (k - 1) * (pw + 6), 1, slotY - SH - 14)
      c.idx.Text = ""
      local on = (sel.kit[slot.id] or false) == id
      local pass = id and G.passFor(id)
      local locked = pass and not passOk(pass)
      c.cat.Text = locked and T("pass.lockTag", Config.Passes[pass].price) or (on and T("deploy.current") or "")
      c.cat.TextColor3 = locked and RGB(255, 196, 92) or FAINT
      c.nm.Text = itemName(id or nil)
      local n = id and countOf(id)
      c.cnt.Text = n and ("×" .. n) or ""
      c.st.Transparency = on and 0.2 or 0.86
      if id then c.wait = setModel(c.vp, id, S.team) c.item = id end
      c.b.Activated:Connect(function()
        if locked then G.buyPass(pass) return end   -- 没解锁：弹出 Roblox 的购买框（买成了属性一变，这里自动刷新）
        sel.kit[slot.id] = id or nil
        sel.slot = nil
        picker.Visible = false
        for _, cc in ipairs(pickCards) do cc.b:Destroy() end
        pickCards = {}
        G.refreshDeploy()
      end)
      table.insert(pickCards, c)
    end
    picker.Visible = true
  end
  for i, c in ipairs(cards) do
    c.b.Activated:Connect(function()
      openPicker(i)
      G.refreshDeploy()
    end)
  end
  G.deployPick = openPicker   -- 测试、截图用：点开 / 收起第 i 格

  local lastTeam = nil
  function G.refreshDeploy()
    local S = G.S
    if not S then return end
    local team = S.team or "atk"
    local tc = teamColor(team)
    autoSpawn(S)
    -- 页：选好了出生点（推荐的自动选上）就先给生成点页，装备用默认的，按一下出击就上战场；想改装备点「改装备」
    local page = sel.pageUser or (sel.spawn and "spawn" or "kit")
    sel.page = page
    kitPage.Visible = page == "kit"
    spawnPage.Visible = page == "spawn"
    for pg, t in pairs(tabs) do
      t.b.Text = T("deploy.tab." .. pg)
      t.b.TextColor3 = (pg == page) and WHITE or DIM
      t.u.BackgroundTransparency = (pg == page) and 0 or 1
      t.u.BackgroundColor3 = WHITE
    end
    langBtn.Text = T("ui.lang")
    sideBtn.Text = T("ui.switchSide")
    menuBtn.Text = T("menu.open")
    -- 阵营一行
    facDot.BackgroundColor3 = tc
    facLine.Text = T("faction." .. team .. ".name") .. "   ·   " .. T((team == "def") and "ui.goalDef" or "ui.goalAtk")
    -- 换了阵营：装备格的样子（两边的模型不一样）重画
    if lastTeam ~= team then
      lastTeam = team
      for _, c in ipairs(cards) do c.item = "?" end
      bigItem = "?"
    end
    -- 装备格
    for i, c in ipairs(cards) do
      local slot = c.slot
      local id = sel.kit[slot.id]
      if not id and not slot.none then id = slot.opts[1] sel.kit[slot.id] = id end
      if id and G.passFor(id) and not passOk(G.passFor(id)) then id = nil sel.kit[slot.id] = nil end   -- 没解锁的（比如通行证刚上架）不带
      c.idx.Text = tostring(i)
      c.cat.Text = T("deploy.slot." .. slot.id)
      c.nm.Text = itemName(id)
      c.nm.TextColor3 = id and WHITE or FAINT
      local n = id and countOf(id)
      c.cnt.Text = n and ("×" .. n) or ""
      local on = (sel.slot == i) or (sel.slot == nil and focus == i)
      c.st.Transparency = on and 0.35 or 0.86
      c.bar.BackgroundTransparency = (sel.slot == i) and 0 or 1
      c.b.BackgroundTransparency = on and 0.25 or 0.4
      if c.item ~= (id or false) then
        c.item = id or false
        c.wait = setModel(c.vp, id, team)
      end
    end
    picker.Visible = sel.slot ~= nil
    -- 兵种那一排：现在这一套正好是哪个兵种的就点亮它（自己改了哪格就都不亮）
    roleRow.Visible = sel.slot == nil
    roleHead.Text = T("deploy.roles")
    local cur = nil
    for _, r in ipairs(Config.RoleKits or {}) do
      local k = Config.roleKit(r.id, team)
      local same = true
      for _, slot in ipairs(SLOTS) do
        if (k[slot.id] or false) ~= (sel.kit[slot.id] or false) then same = false break end
      end
      if same and (cur == nil or sel.kitRole == r.id) then cur = r.id end
    end
    for id, rb in pairs(roleBtns) do
      rb.b.Text = T("kitrole." .. id)
      rb.b.TextColor3 = (id == cur) and WHITE or DIM
      rb.b.Font = (id == cur) and Enum.Font.BuilderSansBold or Enum.Font.BuilderSansMedium
      rb.u.BackgroundTransparency = (id == cur) and 0 or 1
    end
    -- 标题、说明、数据、大图：看的那一格
    local fs = SLOTS[focus] or SLOTS[1]
    local fid = sel.kit[fs.id]
    bigName.Text = fid and itemName(fid) or T("deploy.none")
    bigDesc.Text = T("deploy.slot." .. fs.id) .. "   ·   " .. (fid and T("gear." .. fid .. ".desc") or T("deploy.noneDesc"))
    local rows = fid and statRows(fid) or {}
    for k, r in ipairs(stats) do
      local d = rows[k]
      local show = d ~= nil and not mobile
      r.a.Visible, r.bg.Visible, r.v.Visible = show, show, show
      if d then
        r.a.Text = d[1]
        r.fill.Size = UDim2.fromScale(d[2], 1)
        r.v.Text = d[3]
      end
    end
    local bkey = fid and (fid .. ((GMods.has(fid) and player:GetAttribute("Gun_" .. fid)) or "")) or false   -- 换了配件也重画大图
    if bigItem ~= bkey then
      bigItem = bkey
      bigWait = setModel(big, fid, team)
    end
    -- 改枪按钮：看的是装得了配件的枪
    local canMod = fid ~= nil and GMods.has(fid) and G.openGunsmith ~= nil
    sel.gsId = canMod and fid or nil
    gsBtn.Visible, gsLine.Visible, gsLv.Visible = canMod, canMod and not mobile, canMod
    if canMod then
      gsBtn.Text = T("gm.open")
      local b = G.myBuild and G.myBuild(fid) or GMods.default(fid)
      local names = {}
      for _, slot in ipairs(GMods.SLOTS) do
        local it = b[slot] and GMods.ITEM[b[slot]]
        if it and it.model then table.insert(names, T("gm.item." .. b[slot])) end
      end
      gsLine.Text = (#names > 0) and table.concat(names, " · ") or T("gm.stock")
      local lv, a, nx = GMods.level(fid, player:GetAttribute("GunXp_" .. fid) or 0)
      gsLv.Text = T("gm.lv", lv) .. (nx and "" or ("  " .. T("gm.max")))
    end
    -- 主按钮
    goSpawnT.Text = T("deploy.pickSpawn")
    goSpawnK.Text = mobile and "" or T("deploy.enter")
    buildSpawns(S)
    listHead.Text = T("deploy.tab.spawn")
    local names = {}
    for _, slot in ipairs(SLOTS) do
      local id = sel.kit[slot.id]
      if id then table.insert(names, itemName(id)) end
    end
    kitLine.Text = T("deploy.kitLine", table.concat(names, " · "))
    editKit.Text = T("deploy.editKit")
    if (S.wait or 0) > 0 then
      deployBtnT.Text = T("ui.waitRespawn", S.wait)
      deployBtn.BackgroundColor3 = RGB(46, 48, 52)
      deployBtnT.TextColor3 = DIM
      deployBtn.AutoButtonColor = false
    else
      deployBtnT.Text = T("ui.deployBtn")
      deployBtn.BackgroundColor3 = WHITE
      deployBtnT.TextColor3 = sel.spawn and RGB(10, 10, 12) or RGB(120, 120, 124)
      deployBtn.AutoButtonColor = true
    end
    deployBtnK.Text = mobile and "" or T("deploy.enter")
  end

  -- 真模型还在生成：隔两秒再要一次（最多等半分钟）
  task.spawn(function()
    for _ = 1, 15 do
      task.wait(2)
      if deploy.Visible and G.S then
        local any = false
        for _, c in ipairs(cards) do if c.wait then c.item = "?" any = true end end
        if bigWait then bigItem = "?" any = true end
        if any then G.refreshDeploy() end
      end
    end
  end)
  -- 大图慢慢左右转（绕模型中心：G.viewFit 记在属性 C 里）
  G.frameConn("UI2", function()
    if not deploy.Visible or not kitPage.Visible then return end
    local m = big:FindFirstChildOfClass("Model")
    local c = m and m:GetAttribute("C")
    if c then pcall(function() m:PivotTo(CFrame.new(c) * CFrame.Angles(0, math.sin(os.clock() * 0.5) * 0.3, 0)) end) end
  end)

  langBtn.Activated:Connect(function()
    G.lang = (G.lang == "zh") and "en" or "zh"
    G.refresh()
  end)

  ---------------------------------------------------------------- 顶栏：时间、据点

  local hud = frame(gui, UDim2.fromScale(1, 1), nil, PANEL, 1)
  hud.Name = "Hud"
  local topBar = frame(hud, UDim2.fromOffset(460, 74), UDim2.new(0.5, 0, 0, 8), PANEL, 0.35, Vector2.new(0.5, 0))
  round(topBar, 10)
  local timer = label(topBar, "", UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 4), 20, TEXT, Enum.Font.BuilderSansExtraBold)
  local chips = {}
  for i, p in ipairs(Map.POINTS) do
    local c = frame(topBar, UDim2.fromOffset(80, 38), UDim2.fromOffset(10 + (i - 1) * 89, 30), RGB(30, 40, 60), 0.05)
    round(c, 6)
    local l = label(c, p.id, UDim2.new(0, 26, 1, 0), UDim2.fromOffset(4, 0), 20, Color3.new(1, 1, 1), Enum.Font.BuilderSansExtraBold)
    local n = label(c, "", UDim2.new(1, -32, 0, 18), UDim2.fromOffset(30, 3), 12, Color3.new(1, 1, 1), Enum.Font.BuilderSansBold, nil, Enum.TextXAlignment.Left)
    local barBg = frame(c, UDim2.new(1, -36, 0, 5), UDim2.new(0, 30, 1, -10), RGB(0, 0, 0), 0.5)
    local bar = frame(barBg, UDim2.fromScale(0, 1), nil, Config.Teams.atk.color, 0)
    chips[p.id] = { f = c, l = l, n = n, bar = bar }
  end
  local counts = label(hud, "", UDim2.fromOffset(240, 20), UDim2.new(0.5, 0, 0, 84), 14, TEXT, Enum.Font.BuilderSansBold, Vector2.new(0.5, 0))
  counts.TextStrokeTransparency = 0.5

  -- 血条
  local hpBg = frame(hud, UDim2.fromOffset(260, 14), UDim2.new(0, 20, 1, -40), RGB(0, 0, 0), 0.45)
  round(hpBg, 4)
  local hpBar = frame(hpBg, UDim2.fromScale(1, 1), nil, RGB(90, 210, 110), 0)
  round(hpBar, 4)
  local hpText = label(hpBg, "", UDim2.fromScale(1, 1), nil, 12, Color3.new(1, 1, 1), Enum.Font.BuilderSansBold)
  local roleText = label(hud, "", UDim2.fromOffset(260, 18), UDim2.new(0, 20, 1, -62), 14, TEXT, Enum.Font.BuilderSansBold, nil, Enum.TextXAlignment.Left)
  roleText.TextStrokeTransparency = 0.5
  local help = label(hud, "", UDim2.new(0.6, 0, 0, 16), UDim2.new(0.5, 0, 1, -18), 12, MUTE, Enum.Font.BuilderSans, Vector2.new(0.5, 0))
  help.TextStrokeTransparency = 0.6

  -- 小地图容器（Hud.lua 摆到右上、画成方形雷达小地图）：CanvasGroup 才能把里面的地图、亮点按框裁掉
  local miniBox = Instance.new("CanvasGroup")
  miniBox.Name = "Radar"
  miniBox.Size, miniBox.Position, miniBox.AnchorPoint = UDim2.fromOffset(230, 230), UDim2.new(1, -16, 1, -16), Vector2.new(1, 1)
  miniBox.BackgroundColor3, miniBox.BackgroundTransparency, miniBox.BorderSizePixel = PANEL, 1, 0
  miniBox.Parent = hud
  -- 地图真正挂在框里这一层（ClipsDescendants 的普通 Frame）：CanvasGroup 的裁边有时不起作用（用户 11-24 截图：开坦克瞄准镜、
  --   小地图挪到 RadarTop 那层以后，2000 多像素的整张图没裁、深蓝的海盖住半个镜子）——这一层再按方框裁一次，怎么都不会漏出来
  local miniClip = Instance.new("Frame")
  miniClip.Name = "MapClip"
  miniClip.Size = UDim2.fromScale(1, 1)
  miniClip.BackgroundTransparency = 1
  miniClip.BorderSizePixel = 0
  miniClip.ClipsDescendants = true
  miniClip.Parent = miniBox
  -- 战斗中的界面换成《坠落》那种风格（Hud.lua）：旧的顶栏、血条、兵种字交给它收起来，小地图框挪到左下
  G.hudParts = { hud = hud, topBar = topBar, counts = counts, hpBg = hpBg, roleText = roleText, miniBox = miniBox, miniClip = miniClip, help = help }

  ---------------------------------------------------------------- 消息

  local center = label(gui, "", UDim2.new(0.8, 0, 0, 40), UDim2.new(0.5, 0, 0.44, 0), 24, Color3.new(1, 1, 1), Enum.Font.BuilderSansBold, Vector2.new(0.5, 0.5))
  center.TextStrokeTransparency = 0.3
  center.ZIndex = 30
  local centerT = 0
  local feed = frame(gui, UDim2.fromOffset(340, 160), UDim2.new(1, -16, 0, 120), PANEL, 1, Vector2.new(1, 0))
  G.hudParts.feed = feed   -- 击杀信息：Hud.lua 把小地图放到右上后挪到它下面
  local feedList = Instance.new("UIListLayout")
  feedList.HorizontalAlignment = Enum.HorizontalAlignment.Right
  feedList.SortOrder = Enum.SortOrder.LayoutOrder
  feedList.Parent = feed
  local toasts = frame(gui, UDim2.fromOffset(440, 200), UDim2.new(0.5, 0, 1, -110), PANEL, 1, Vector2.new(0.5, 1))
  local toastList = Instance.new("UIListLayout")
  toastList.VerticalAlignment = Enum.VerticalAlignment.Bottom
  toastList.HorizontalAlignment = Enum.HorizontalAlignment.Center
  toastList.Padding = UDim.new(0, 4)
  toastList.SortOrder = Enum.SortOrder.LayoutOrder
  toastList.Parent = toasts
  local order = 0
  -- 跟新界面一个样子（深色、直角、细线）：底是深色，左边一道颜色细条分好消息、坏消息、击杀
  local KIND_COL = { good = TH.C.GOOD, bad = TH.C.BAD, info = TH.C.MUTE, kill = TH.C.WARN }
  function G.toast(text, kind)
    order += 1
    local l = label(toasts, text, UDim2.fromOffset(420, 28), nil, 14, TEXT, Enum.Font.BuilderSansMedium)
    l.BackgroundColor3 = RGB(6, 8, 10)
    l.BackgroundTransparency = 0.2
    l.LayoutOrder = order
    stroke(l, LINE, 1, 0.9)
    frame(l, UDim2.new(0, 3, 1, 0), nil, KIND_COL[kind or "info"] or KIND_COL.info, 0)
    task.delay(4, function() l:Destroy() end)
  end
  function G.centerMsg(text)
    center.Text = text
    center.TextTransparency = 0
    centerT = os.clock()
  end
  local function feedAdd(text)
    order += 1
    local l = label(feed, text, UDim2.fromOffset(340, 22), nil, 14, Color3.new(1, 1, 1), Enum.Font.BuilderSansBold, nil, Enum.TextXAlignment.Right)
    l.TextStrokeTransparency = 0.4
    l.LayoutOrder = order
    local kids = {}
    for _, c in ipairs(feed:GetChildren()) do if c:IsA("TextLabel") then table.insert(kids, c) end end
    if #kids > 6 then table.sort(kids, function(a, b) return a.LayoutOrder < b.LayoutOrder end) kids[1]:Destroy() end
    task.delay(8, function() l:Destroy() end)
  end

  -- 服务器发来的文字：kind、编号、参数（参数里的 { k = 编号 } 也翻译）
  function G.onMsg(kind, key, ...)
    if kind == "hit" then
      if G.hitMarker then G.hitMarker(key) end
      return
    end
    if kind == "hurt" then   -- 挨打：伤害从哪来（Juice.lua 在准星周围画红弧），key 是位置
      if G.juiceHurt and typeof(key) == "Vector3" then G.juiceHurt(key) end
      return
    end
    -- 试驾场里不报主战场的事（用户 11-25 晚「训练场为什么会有missionfailed 还有一堆乱七八糟的据点占领啥的」）：
    --   占点、阶段、兵力、胜负、任务、击杀栏都不弹；试驾自己的提示（Tech.lua 发的 tech.* / wt.*）照常
    if G.inTestDrive and G.inTestDrive() then
      local k = type(key) == "string" and key or ""
      if kind == "center" or kind == "stage" or kind == "feed" or k:find("^ui%.captur") or k:find("^ui%.flank") or k:find("^ui%.lost")
        or k:find("^ui%.tickets") or k:find("^ui%.win") or k:find("^ui%.conquest") or k:find("^wtm%.") or k:find("^pve%.") or k:find("^stage%.") then
        return
      end
    end
    if key == "ui.capturedYou" and G.juiceScore then G.juiceScore(G.Config.Score.capture, T("juice.cap")) end
    if kind == "ric" then   -- 跳弹（服务器 Ents.lua）：准星下面弹一行黄字（打出去的跳了 / 打过来的被弹开）
      if G.pop then G.pop(T(key, ...), key == "hit.ricIn" and "ricIn" or "ric") end
      return
    end
    if kind == "refill" then   -- 战术平板的补给箱：本地弹药也补满（Play.lua）
      if G.refillAmmo then G.refillAmmo() end
      return
    end
    if kind == "stage" then   -- Operation.lua 直接从战况读阶段，中途入场也会显示简报。
      if not G.stepOperation then G.centerMsg(T(key)) end
      return
    end
    local text = T(key, ...)
    -- 击杀、自己占下据点：准星下面弹一行（Hud.lua G.pop），右上角照样留一条
    if G.pop and (kind == "kill" or key == "ui.capturedYou") then G.pop(text, kind) end
    if kind == "center" then G.centerMsg(text)
    elseif kind == "feed" then feedAdd(text)
    elseif kind == "kill" then   -- 击杀：准星下面那一行（或开车时命中结果的「已击毁」）+ 左边击杀栏已经有了，不再在下面弹第三条（统一外观：一件事只报一处）
    else G.toast(text, kind) end
  end

  ---------------------------------------------------------------- 战况表（按住 Tab）

  -- 跟新界面一个样子：深色、直角、细线（用户：要精致简洁，不要卡通）
  local board = frame(gui, UDim2.fromOffset(780, 520), UDim2.fromScale(0.5, 0.52), RGB(6, 8, 10), 0.08, Vector2.new(0.5, 0.5))
  board.Visible = false
  board.ZIndex = 20
  stroke(board, LINE, 1, 0.88)
  local boardTitle = label(board, "", UDim2.new(1, -48, 0, 40), UDim2.fromOffset(24, 8), 16, TEXT, Enum.Font.BuilderSansBold, nil, Enum.TextXAlignment.Left)
  boardTitle.ZIndex = 21
  local cols = {}
  for i, t in ipairs({ "atk", "def" }) do
    local c = frame(board, UDim2.new(0.5, -36, 1, -64), UDim2.new((i - 1) * 0.5, 24, 0, 52), RGB(0, 0, 0), 1)
    c.ZIndex = 21
    local tl = frame(c, UDim2.new(1, 0, 0, 2), nil, teamColor(t), 0)   -- 顶上一道队色细线
    tl.ZIndex = 22
    local h = label(c, "", UDim2.new(1, 0, 0, 28), UDim2.fromOffset(0, 6), 14, TEXT, Enum.Font.BuilderSansBold, nil, Enum.TextXAlignment.Left)
    h.ZIndex = 22
    local list = Instance.new("Frame")
    list.BackgroundTransparency = 1
    list.Size = UDim2.new(1, -8, 1, -32)
    list.Position = UDim2.fromOffset(4, 30)
    list.ZIndex = 22
    list.Parent = c
    local ll = Instance.new("UIListLayout")
    ll.SortOrder = Enum.SortOrder.LayoutOrder
    ll.Parent = list
    cols[t] = { head = h, list = list }
  end
  local boardData = {}
  local drawnData, drawnLang = nil, nil   -- 上次画的是哪一份数据、哪种语言：按 Tab 打开时数据没变就不再整张重建（几十行、上百个字）
  function G.onBoard(d) boardData = d or {} if board.Visible then G.drawBoard() end end
  function G.drawBoard()
    if drawnData == boardData and drawnLang == G.lang then return end
    drawnData, drawnLang = boardData, G.lang
    boardTitle.Text = T("ui.scoreboard")
    for t, c in pairs(cols) do
      for _, k in ipairs(c.list:GetChildren()) do if k:IsA("Frame") then k:Destroy() end end
      local rows = {}
      for _, e in ipairs(boardData) do if e.t == t then table.insert(rows, e) end end
      table.sort(rows, function(a, b) return (a.s or 0) > (b.s or 0) end)
      c.head.Text = T("hud." .. t) .. "   ·   " .. T("team." .. t) .. "   " .. #rows
      local hdr = frame(c.list, UDim2.new(1, 0, 0, 18), nil, PANEL, 1)
      hdr.LayoutOrder = 0
      hdr.ZIndex = 22
      for k, txt in ipairs({ "", T("ui.kills"), T("ui.deaths"), T("ui.captures"), T("ui.score") }) do
        local l = label(hdr, txt, UDim2.new(k == 1 and 0.44 or 0.14, 0, 1, 0), UDim2.new(k == 1 and 0 or (0.44 + (k - 2) * 0.14), 0, 0, 0), 10, MUTE, Enum.Font.BuilderSansMedium)
        l.ZIndex = 23
      end
      for i, e in ipairs(rows) do
        if i > 22 then break end
        local r = frame(c.list, UDim2.new(1, 0, 0, 20), nil, RGB(255, 255, 255), (e.id == player.UserId) and 0.9 or 1)
        r.LayoutOrder = i
        r.ZIndex = 22
        local nm = e.n .. (e.bot and (" " .. T("ui.bot")) or "")
        for k, txt in ipairs({ nm, tostring(e.k or 0), tostring(e.d or 0), tostring(e.c or 0), tostring(e.s or 0) }) do
          local l = label(r, txt, UDim2.new(k == 1 and 0.44 or 0.14, 0, 1, 0), UDim2.new(k == 1 and 0 or (0.44 + (k - 2) * 0.14), 0, 0, 0), 12, TEXT,
            Enum.Font.BuilderSansMedium, nil, k == 1 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center)
          l.ZIndex = 23
          l.TextTruncate = Enum.TextTruncate.AtEnd
        end
      end
    end
  end
  UIS.InputBegan:Connect(function(io, gp)
    if io.KeyCode == Enum.KeyCode.Tab then
      G.drawBoard()   -- 先画好再弹出来（同一帧）
      G.uiShow(board, true)
    end
    G.boardShown = function() return board.Visible end
  end)
  UIS.InputEnded:Connect(function(io)
    if io.KeyCode == Enum.KeyCode.Tab then G.uiShow(board, false) end
  end)
  local boardBtn = button(hud, "≡", UDim2.fromOffset(36, 36), UDim2.new(0, 16, 0, 70), RGB(8, 10, 12))   -- 顶栏下面：左上角是 Roblox 自带的菜单、聊天按钮
  boardBtn.BackgroundTransparency = 0.5
  boardBtn.TextColor3 = RGB(200, 206, 210)
  for _, c in ipairs(boardBtn:GetChildren()) do if c:IsA("UICorner") then c:Destroy() end end   -- 直角，跟新界面一样
  boardBtn.TextSize = 22
  boardBtn.Activated:Connect(function()
    if board.Visible then G.uiShow(board, false)
    else
      G.drawBoard()
      G.uiShow(board, true)
    end
  end)

  ---------------------------------------------------------------- 结算

  -- 跟战况表一个样子：深色、直角、细线；顶上一道胜方的队色细线，四个大数字，经验、军衔，下一局倒计时
  local results = frame(gui, UDim2.fromOffset(640, 286), UDim2.fromScale(0.5, 0.46), RGB(6, 8, 10), 0.08, Vector2.new(0.5, 0.5))
  results.Visible = false
  results.ZIndex = 25
  stroke(results, LINE, 1, 0.88)
  local resLine = frame(results, UDim2.new(1, 0, 0, 2), nil, LINE, 0)
  local resCap = label(results, "", UDim2.new(1, -56, 0, 16), UDim2.fromOffset(28, 22), 11, MUTE, Enum.Font.BuilderSansMedium, nil, Enum.TextXAlignment.Left)
  local resTitle = label(results, "", UDim2.new(1, -56, 0, 42), UDim2.fromOffset(28, 40), 34, TEXT, Enum.Font.BuilderSansBold, nil, Enum.TextXAlignment.Left)
  local resSub = label(results, "", UDim2.new(1, -56, 0, 20), UDim2.fromOffset(28, 86), 14, MUTE, Enum.Font.BuilderSansMedium, nil, Enum.TextXAlignment.Left)
  local resNums = {}
  for i, k in ipairs({ "ui.kills", "ui.deaths", "ui.captures", "ui.score" }) do
    local x = 28 + (i - 1) * 146
    resNums[i] = {
      k = k,
      n = label(results, "0", UDim2.fromOffset(130, 38), UDim2.fromOffset(x, 124), 30, TEXT, Enum.Font.BuilderSansMedium, nil, Enum.TextXAlignment.Left),
      c = label(results, "", UDim2.fromOffset(130, 14), UDim2.fromOffset(x, 164), 11, MUTE, Enum.Font.BuilderSansMedium, nil, Enum.TextXAlignment.Left),
    }
  end
  local resSep = frame(results, UDim2.new(1, -56, 0, 1), UDim2.fromOffset(28, 196), LINE, 0.88)
  local resXp = label(results, "", UDim2.new(1, -56, 0, 20), UDim2.fromOffset(28, 208), 14, TEXT, Enum.Font.BuilderSansMedium, nil, Enum.TextXAlignment.Left)
  local resNext = label(results, "", UDim2.new(1, -56, 0, 18), UDim2.new(0, 28, 1, -40), 12, MUTE, Enum.Font.BuilderSansMedium, nil, Enum.TextXAlignment.Left)
  for _, x in ipairs({ resLine, resCap, resTitle, resSub, resSep, resXp, resNext }) do x.ZIndex = 26 end
  for _, r in ipairs(resNums) do r.n.ZIndex, r.c.ZIndex = 26, 26 end
  if mobile then   -- 手机横屏（844 × 390）：缩一点，别盖住触屏按钮
    local sc = Instance.new("UIScale")
    sc.Scale = 0.8
    sc.Parent = results
  end

  ---------------------------------------------------------------- 刷新（收到服务器状态时）

  local mapMountedIn = nil
  function G.refresh()
    local S = G.S
    if not S then return end
    if G.refreshMapPick then G.refreshMapPick(S) end   -- 选地图界面（MapPick.lua）：生成地图时也要刷进度、生成好了快速加入
    if (S.progress or 1) < 1 then
      loading.Visible = true
      loadText.Text = T("ui.serverStarting", math.floor((S.progress or 0) * 100))
      return
    end
    loading.Visible = false
    if G.refreshMenu then G.refreshMenu(S) end         -- 主菜单（Menu.lua）：进服先到这里
    if G.refreshFaction then G.refreshFaction(S) end   -- 选阵营界面（Faction.lua）：主菜单点了「进入战斗」还没选、或者点了「换阵营」
    -- 阵亡效果（DeathFx.lua，用户 11-23：死亡不要瞬间切到部署画面）放着的时候部署界面、平显都先不出来
    local dying = G.deathFxOn ~= nil and G.deathFxOn() == true
    local showDeploy = not S.alive and S.phase ~= "end" and not dying
    if S.alive then sel.pageUser, sel.slot = nil, nil end   -- 下次阵亡：上次出击过就先给生成点页
    local menuOn = G.menuShown and G.menuShown()
    -- 机库（TechUI.lua，用户 11-25「就跟战雷完全一样 不要让玩家作为个体活动」）：开着 Config.Wt.noInfantry 时盖住步兵部署页，从出击阵容里挑车出击
    if G.hangarSet then G.hangarSet(showDeploy and not menuOn) end   -- 局内选车也是这一页（TechUI.lua：服务器 S.pick 时主按钮「出击」）
    deploy.Visible = showDeploy and not menuOn and not (G.hangarActive and G.hangarActive())   -- 主菜单开着（背景是透明的 3D 场景）：部署界面先不画
    hud.Visible = not showDeploy and not dying
    results.Visible = S.phase == "end" and not (G.wtResultsOn and G.wtResultsOn())   -- 战雷式结算页（WtBattle.lua）开着就不画这张
      and not (G.inTestDrive and G.inTestDrive())   -- 还在试驾场里：这一局的结算都不弹
    -- 地图放在部署界面或小地图里
    local want = showDeploy and mapHolder or miniClip
    if mapMountedIn ~= want then
      mapMountedIn = want
      local _, marks = G.mapMount(want, UDim2.fromScale(1, 1))
      spawnLayer = marks
    end
    if G.mapRefresh then G.mapRefresh(S) end
    if showDeploy then
      G.refreshDeploy()
      if S.phase == "prep" then phaseText.Text = T("ui.prep", S.left) else phaseText.Text = T("ui.timeLeft") .. "  " .. fmtTime(S.left) end
    else
      for _, b in ipairs(spawnBtns) do b:Destroy() end
      spawnBtns = {}
    end
    -- 顶栏
    if S.phase == "prep" then
      timer.Text = T("ui.prep", S.left)
    elseif S.ot then
      timer.Text = T("ui.overtime") .. "  " .. fmtTime(S.ot)
    else
      timer.Text = fmtTime(S.left)
    end
    for _, s in ipairs(S.points or {}) do
      local c = chips[s.id]
      if c then
        c.f.BackgroundColor3 = teamColor(s.owner):Lerp(Color3.new(0, 0, 0), 0.25)
        c.bar.Size = UDim2.fromScale(s.locked and 1 or s.prog, 1)
        c.n.Text = s.locked and "" or ((s.atk > 0 or s.def > 0) and (T("team.atk.short") .. s.atk .. " " .. T("team.def.short") .. s.def) or "")
      end
    end
    counts.Text = T("team.atk") .. " " .. (S.nAtk or 0) .. "   ·   " .. T("team.def") .. " " .. (S.nDef or 0)
    roleText.Text = (S.role and T("role." .. S.role) or "") .. "  ·  " .. T("team." .. (S.team or "atk"))
    roleText.TextColor3 = teamColor(S.team)
    if S.phase == "end" then
      local won = S.winner == S.team
      resLine.BackgroundColor3 = teamColor(S.winner)
      resCap.Text = T("ui.roundOver")
      resTitle.Text = T(won and "ui.youWon" or "ui.youLost")
      resTitle.TextColor3 = won and TEXT or RGB(236, 120, 108)
      resSub.Text = T((S.winner == "atk") and "ui.win.atk" or "ui.win.def") .. (S.mvp and ("   ·   MVP  " .. S.mvp) or "")
      local me = S.me or {}
      local vals = { me.k or 0, me.d or 0, me.c or 0, me.s or 0 }
      for i, r in ipairs(resNums) do
        r.n.Text = tostring(vals[i])
        r.c.Text = T(r.k)
      end
      resXp.Text = T("ui.xp", me.gain or 0) .. "   ·   " .. Lang.rank(G.lang, me.rank or 1)
      resNext.Text = T("ui.nextRound", S.left)
    end
  end

  function G.stepUI(dt)
    -- 开着载具 / 飞机 / 火炮：血条、兵种看载具面板；最下面一行换成载具的操作说明（面板里放不下一整行）
    local drv = G.drive
    hpBg.Visible, roleText.Visible = not drv, not drv
    help.Text = T(drv and (drv.help or "ui.vehHelp") or "ui.help")
    -- 手机上是触屏按钮，不显示键盘说明；步行第一人称也不显示（用户：持枪第一视角不要显示鼠标、键位；键位说明在部署界面最下面）
    help.Visible = not G.coachOn and not G.mobile and not (G.fpActive and not drv)   -- Coach.lua 换成按当前状态的几个键（全文在 F1）
    deployHelp.Text = T("ui.help")
    -- 鼠标指针：游戏里锁在屏幕中间时（第一人称、肩后瞄准、开车开飞机开船、操作工事）不画——准星是自己画的；开着菜单时画出来
    if not G.mobile then
      local menu = G.menuOpen()
      local xr = G.ownXrayOn ~= nil and G.ownXrayOn()   -- 按住 X 透视自己的车：鼠标放开了（Drive.lua），画出指针去指部件
      local locked = not menu and not xr and (UIS.MouseBehavior == Enum.MouseBehavior.LockCenter or (G.fpActive and not drv) or drv ~= nil)
      if UIS.MouseIconEnabled == locked then UIS.MouseIconEnabled = not locked end
      if menu and UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then UIS.MouseBehavior = Enum.MouseBehavior.Default end
    end
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
      local k = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
      hpBar.Size = UDim2.fromScale(k, 1)
      hpBar.BackgroundColor3 = RGB(230, 70, 60):Lerp(RGB(90, 210, 110), k)
      hpText.Text = math.ceil(hum.Health) .. " / " .. math.ceil(hum.MaxHealth)
    end
    local a = os.clock() - centerT
    local fade = results.Visible and 1 or math.clamp((a - 3) / 1, 0, 1)   -- 结算面板开着：中间那行大字（胜负原因）面板上有了，不叠着画
    center.TextTransparency = fade
    center.TextStrokeTransparency = 0.3 + 0.7 * fade
  end
end

return UI
