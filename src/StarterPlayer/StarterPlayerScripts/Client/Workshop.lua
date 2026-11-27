-- 全面大战场（客户端）——整备（Workshop）外壳：在机库里给选中的那一辆配挂载 / 弹药、改装、乘员、涂装、看资料
--   用户 11-27：「整个给载具配置武器的系统 做的很粗糙 我需要非常艺术经验的效果 参考战雷」——同类写实军事游戏那种精致、克制、写实的质感，
--   用我们自己的界面美术（docs/style.md、Theme.lua；零件在 WsKit.lua）。舞台就是机库现成的 3D 厂房 / 停机坪（HangarStage），不另开视口；
--   界面和机库同一块 1280 × 720 缩放的画布（TechUI 的 Root）：
--   · 0～92：机库顶栏照旧（「加入战斗」仍是这一屏唯一的主按钮；顶栏上和页签重复的扳手、弹药、资料键整备时收起：TechUI G.hangarWsMode）；
--     「这一局」那块、国旗、乘员框、选中车的资料、阵容卡、科技树把手也收起
--   · 抬头 80～120：左边「‹ 机库」（不画框：灰字、悬停变白）、车名（标题 21）、保存状态（车名右边：「自动保存」→ 服务器回了「已保存 ✓」→ 淡回去；
--     没存上琥珀「没存上 · 重试」）、下一行「中国 · VII 级 · BR 13.3」（粗 13 灰）；右边页签「挂载（地面车：弹药）· 改装 · 乘员 ·（涂装）· 资料」——
--     选中白底黑字（一屏白底只有页签 + 主按钮），没选中的不填底、不描边、灰字，页签组下面一道 1 像素底线。飞机没有涂装（现在只有地面车会上色），页签直接不放。
--     这一轮只有「挂载」是新做的（WsArms.lua），其余先打开现有的面板（G.openMods / openCrew / openSkin / openInfo / openAmmo），关了回到挂载页
--   · 左栏 x 24 宽 300、右栏靠右宽 320（132～580，高度跟着内容走：ws.fitCol）、底部条 592～696（高 104；上面一行 22 高放名牌、左右对称）；
--     左右两边各一块压暗的渐变（BG 色，外侧 0.35 → 里侧 1）：字清楚、中间的飞机像被打了光；右下角「拖动转 · 滚轮缩放 · 右键返回」
--   · 进场：两栏从两边滑进 24 像素 + 淡入、底部条从下面上来、抬头往下落一点（0.28 秒先快后慢），镜头飞到全景（0.55 秒两头慢）；
--     退场只淡出（0.18 秒）。CanvasGroup 只在这两段时间里用（平时是普通 Frame：CanvasGroup 在部分设备上把里面画成一张贴图，字会发糊）
--   · 返回（一层层退：开着的旧面板 → 选着的挂点 → 回机库）：「‹ 机库」、右键、Backspace；3D 空白处点一下只在整备里面退（不退出整备）；
--     Esc 也认，但 Roblox 按 Esc 会开系统菜单（引擎行为）：菜单开着、或者这一下是去开 / 关菜单的，都不算返回。Ctrl+Z 撤销（页自己的 undo）
--   · 改动即时存（不设「保存」键）
--   手机（1000 × 500 画布）：两栏收窄（236 / 244）、底部条 84 高、挂点卡横着卷；能点的东西都 ≥ 44 高（页签、小块、「‹ 机库」、内油、左右对称）
--   G.openWorkshop(科技树的项, 页签)、G.closeWorkshop(马上)、G.workshopOpen()、G.workshopState()（测试用）
--   入口：机库顶栏的弹药键（飞机 / 直升机；地面车这一轮照旧开配弹面板）
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Workshop = {}

function Workshop.init(G)
  local TT = require(RS:WaitForChild("TechTree"))
  local WM = require(RS:WaitForChild("WtMods"))
  local K = require(script.Parent:WaitForChild("WsKit"))
  local WsArms = require(script.Parent:WaitForChild("WsArms"))
  local TH = K.TH
  local C, A, S = TH.C, TH.A, TH.S
  local me = Players.LocalPlayer
  local UD2, V2 = UDim2.new, Vector2.new
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local zh = G.lang == "zh"
  local compact = G.mobile == true or (UIS.TouchEnabled and not UIS.KeyboardEnabled)
  -- 排版（Root 画布上的像素）：M 边距、HY / HH 抬头、TOP 两栏的上沿、LW / RW 两栏宽、BH / BM 底部条的高和离下边多远、GAP 间距、DW 悬停资料卡宽、
  --   PLATE 底部条上面那一行（名牌、左右对称）、HIT 能点的东西最少多高（手机 44 ≈ 34pt）
  local LAY = compact and { M = 12, HY = 52, HH = 44, TOP = 104, LW = 236, RW = 244, BH = 84, BM = 10, GAP = 8, DW = 0, TABW = 84, TABH = 44, BACKW = 84, HIT = 44, PLATE = 22 }
    or { M = 24, HY = 80, HH = 40, TOP = 132, LW = 300, RW = 320, BH = 104, BM = 24, GAP = 12, DW = 300, TABW = 96, TABH = 30, BACKW = 80, HIT = 30, PLATE = 22 }

  local W = { on = false, tab = nil, it = nil, key = nil, panel = nil, page = nil }
  local ui = { blocks = {} }
  local built = false
  local H = nil   -- TechUI 的 G.hangarParts（vw × vh 是缩放后的画布、scale 是缩放倍数）
  local ws = { K = K, T = T, LAY = LAY, compact = compact }
  function ws.vw() return (H and H.vw) or 1280 end
  function ws.vh() return (H and H.vh) or 720 end
  function ws.scale() return (H and H.scale) or 1 end
  function ws.colH() return ws.vh() - LAY.TOP - LAY.BM - LAY.BH - LAY.GAP end
  function ws.barTop() return ws.vh() - LAY.BM - LAY.BH end   -- 底部条的上沿（Root 坐标）
  local arms = nil

  ---------------------------------------------------------------- 搭（第一次打开时：TechUI 的机库界面得先搭好）

  -- 一块（抬头、左栏、右栏、底部条、资料卡）：平时是普通的 Frame；进场 / 退场那一小段才临时放进一个 CanvasGroup（fader）里整体滑动、淡入淡出，动完放回来
  local function block(name, size, pos, anchor, z)
    local h = Instance.new("Frame")
    h.Name = name
    h.BackgroundTransparency = 1
    h.BorderSizePixel = 0
    h.Size, h.Position, h.AnchorPoint = size, pos, anchor or V2(0, 0)
    h.ZIndex = z or 2
    h.Parent = ui.root
    local f = Instance.new("CanvasGroup")
    f.Name = name .. "Fade"
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    f.ZIndex = z or 2
    f.Visible = false
    f.Parent = ui.root
    ui.blocks[h] = { fade = f, pos = pos, anchor = anchor or V2(0, 0), tok = nil }
    return h
  end
  local function wrap(h)   -- 放进 CanvasGroup（照这块现在的大小、位置）
    local b = ui.blocks[h]
    local f = b.fade
    if h.Parent == f then return f end
    f.Size, f.AnchorPoint, f.Position = h.Size, h.AnchorPoint, h.Position
    f.GroupTransparency = 0
    f.Visible = true
    h.Parent = f
    h.AnchorPoint, h.Position, h.Size = V2(0, 0), UD2(0, 0, 0, 0), UD2(1, 0, 1, 0)
    return f
  end
  local function unwrap(h)   -- 放回来（停在这块的原位）
    local b = ui.blocks[h]
    local f = b.fade
    if h.Parent ~= f then return end
    h.Size, h.AnchorPoint, h.Position = f.Size, b.anchor, b.pos
    h.Parent = ui.root
    f.Visible = false
  end
  local function holderOf(h)   -- 这块现在是谁在管大小（在 CanvasGroup 里时是它）
    local b = ui.blocks[h]
    return (b and h.Parent == b.fade) and b.fade or h
  end
  local function build()
    local hg = G.hangarGui
    H = G.hangarParts
    if not (hg and H) then return false end
    ws.Stage = G.hangarStage
    local root = K.frame(hg, UD2(1, 0, 1, 0), nil, nil, 1)
    root.Name = "Workshop"
    root.ZIndex = 3
    root.Visible = false
    ui.root = root
    -- 两边压暗（标签层下面）：BG 色，外侧 0.35 → 里侧 1——两栏的字不被背后的机库压着，中间的飞机更像被打了光（底下那一块 TechUI 的机库本来就有）
    for i = 1, 2 do
      local left = i == 1
      local sh = K.frame(root, UD2(0, 420, 1, 0), UD2(left and 0 or 1, 0, 0, 0), C.BG, 0, V2(left and 0 or 1, 0))
      sh.Name = left and "WsShadeL" or "WsShadeR"
      sh.ZIndex = 0
      local g = Instance.new("UIGradient")
      g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, left and 0.35 or 1), NumberSequenceKeypoint.new(1, left and 1 or 0.35) })
      g.Parent = sh
    end
    -- 3D 标签层（两栏、底部条压在它上面）
    local lab = K.frame(root, UD2(1, 0, 1, 0), nil, nil, 1)
    lab.Name = "WsLabels"
    lab.ZIndex = 1
    ws.labels = lab
    -- 抬头：「‹ 机库」、车名、保存状态、国家 · 等级 · BR；右边页签
    local head = block("WsHead", UD2(1, -2 * LAY.M, 0, LAY.HH), UD2(0, LAY.M, 0, LAY.HY), nil, 3)
    ui.head = head
    local back = K.button(head, UD2(0, LAY.BACKW, 0, LAY.HIT), UD2(0, -6, 0.5, 0), "WsBack")
    back.AnchorPoint = V2(0, 0.5)
    local chev = K.chevron(back, 6, LAY.HIT / 2 - 6, 12, C.MUTE)   -- 「‹」画出来（不靠字体）
    local bl = K.text(back, T("ws.back"), S.small, "bold", C.MUTE, UD2(1, -24, 1, 0), UD2(0, 22, 0, 0))
    bl.Name = "Label"
    back.MouseEnter:Connect(function()
      bl.TextColor3 = C.TEXT
      K.tintChevron(chev, C.TEXT)
    end)
    back.MouseLeave:Connect(function()
      bl.TextColor3 = C.MUTE
      K.tintChevron(chev, C.MUTE)
    end)
    back.Activated:Connect(function() if W.on then G.closeWorkshop() end end)
    local nx = LAY.BACKW + 6
    ui.nx = nx
    ui.name = K.text(head, "", compact and S.sub or S.title, "title", C.TEXT, UD2(0, 420, 0, compact and 22 or 24), UD2(0, nx, 0, compact and 1 or -1))
    ui.name.Name = "WsName"
    ui.sub = K.text(head, "", compact and S.tiny or S.small, "bold", C.MUTE, UD2(0, 420, 0, 16), UD2(0, nx, 1, compact and -18 or -15))
    ui.sub.Name = "WsSub"
    -- 保存状态（车名右边）
    local sv = K.button(head, UD2(0, 150, 0, compact and 22 or 24), UD2(0, nx + 120, 0, compact and 1 or -1), "WsSave")
    sv.Active = false
    ui.saveTick = K.tick(sv, 0, (compact and 22 or 24) / 2 - 5, 10, C.MUTE)
    ui.saveTick.Visible = false
    ui.saveT = K.text(sv, T("ws.autosave"), S.tiny, "bold", C.FAINT, UD2(1, -16, 1, 0), UD2(0, 0, 0, 0))
    ui.saveT.Name = "Label"
    sv.Activated:Connect(function()
      local f = W.saveFail
      if f and f.retry then
        W.saveFail = nil
        f.retry()
      end
    end)
    ui.save = sv
    -- 左栏、右栏（面板：深色 0.06 + 细线；高度跟着内容走）
    local colH = -(LAY.TOP + LAY.BM + LAY.BH + LAY.GAP) + 2
    local lg = block("WsLeft", UD2(0, LAY.LW + 2, 1, colH), UD2(0, LAY.M - 1, 0, LAY.TOP - 1), nil, 2)
    ui.lg = lg
    ws.left = K.panel(lg, UD2(1, -2, 1, -2), UD2(0, 1, 0, 1), nil, 0.06)
    ws.left.Name = "Panel"
    local rg = block("WsRight", UD2(0, LAY.RW + 2, 1, colH), UD2(1, -LAY.M + 1, 0, LAY.TOP - 1), V2(1, 0), 2)
    ui.rg = rg
    ws.right = K.panel(rg, UD2(1, -2, 1, -2), UD2(0, 1, 0, 1), nil, 0.06)
    ws.right.Name = "Panel"
    -- 底部条（挂点卡自己是卡片，条本身透明）；上面一行（名牌、左右对称）
    local bg = block("WsBottom", UD2(1, -2 * LAY.M + 4, 0, LAY.BH + 6 + LAY.PLATE), UD2(0, LAY.M - 2, 1, -LAY.BM + 3), V2(0, 1), 2)
    ui.bg = bg
    local bp = K.frame(bg, UD2(1, -4, 0, LAY.BH), UD2(0, 2, 1, -(LAY.BH + 3)), nil, 1)
    bp.Name = "Bar"
    bp.Active = true
    ws.bottom = bp
    local bh = K.frame(bg, UD2(1, -4, 0, LAY.PLATE), UD2(0, 2, 0, 0), nil, 1)
    bh.Name = "BarHead"
    ws.barHead = bh
    -- 悬停资料卡（桌面）：浮在左栏右边，位置固定（页定：武器列表的上沿）
    local dg = block("WsDetail", UD2(0, math.max(LAY.DW, 10) + 2, 0, 252), UD2(0, LAY.M + LAY.LW + LAY.GAP, 0, LAY.TOP), nil, 4)
    dg.Visible = false
    ui.dg = dg
    ws.detail = dg
    -- 右下角的提示（手机不写：没有滚轮、没有右键）
    if not compact then
      ui.hint = K.text(root, T("ws.hint"), S.tiny, "body", C.FAINT, UD2(0, 420, 0, 14), UD2(1, -LAY.M, 1, -5), Enum.TextXAlignment.Right, V2(1, 1))
      ui.hint.Name = "WsHint"
    end
    -- 浮在 3D 上的这几块挡住后面的拖车（TechUI：按位置挡）：平时的 Frame 和进退场时的 CanvasGroup 都登记
    G.stageBlockers = G.stageBlockers or {}
    for _, g in ipairs({ head, lg, rg, bg, dg }) do
      G.stageBlockers[g] = true
      G.stageBlockers[ui.blocks[g].fade] = true
    end
    return true
  end

  ---------------------------------------------------------------- 资料卡的位置、栏高、保存状态（页调用）

  -- 资料卡固定在左栏右边、武器列表上沿那一高（Root 坐标的 y）：换卡只换内容，不跟着卡片跳
  function ws.detailAt(y)
    local b = ui.blocks[ui.dg]
    b.pos = UD2(0, LAY.M + LAY.LW + LAY.GAP, 0, y)
    if ui.dg.Parent ~= b.fade then ui.dg.Position = b.pos end
  end
  -- 资料卡出来（第一次：0.12 秒淡入）/ 收起
  function ws.detailShow(on)
    local h = ui.dg
    local b = ui.blocks[h]
    if on then
      if h.Visible then return end
      h.Visible = true
      local f = wrap(h)
      f.Position = b.pos
      f.GroupTransparency = 1
      TH.tween(f, { GroupTransparency = 0 }, "hover", "out")
      local tok = {}
      b.tok = tok
      task.delay(TH.T.hover + 0.03, function() if b.tok == tok then unwrap(h) end end)
    else
      b.tok = nil
      unwrap(h)
      h.Visible = false
    end
  end
  -- 栏高跟着内容走：h 是内容高；超过整栏就是整栏；0.22 秒补间（instant：马上）
  function ws.fitCol(side, h, instant)
    local blk = (side == "left") and ui.lg or ui.rg
    if not blk then return end
    local hh = math.clamp(math.floor((h or 0) + 0.5), 40, ws.colH()) + 2
    local sz = UD2(0, ((side == "left") and LAY.LW or LAY.RW) + 2, 0, hh)
    local tgt = holderOf(blk)
    if instant or tgt.Size == sz then
      tgt.Size = sz
    else
      TH.tween(tgt, { Size = sz }, "ui", "out")
    end
  end
  -- 保存状态：idle 淡淡的「自动保存」、ok「已保存 ✓」（淡入 0.12、停 1.2、0.6 秒淡回 idle）、fail 琥珀「没存上 · 重试」（点了重发）
  local function saveUI(state)
    local lab, tk, b = ui.saveT, ui.saveTick, ui.save
    if not lab then return end
    W.saveTok = {}
    local tok = W.saveTok
    b.Active = state == "fail"
    if state == "ok" then
      tk.Visible = true
      lab.Position = UD2(0, 14, 0, 0)
      lab.Text = T("ws.saved")
      lab.TextColor3 = C.MUTE
      lab.TextTransparency = 1
      TH.tween(lab, { TextTransparency = 0 }, "hover", "out")
      task.delay(TH.T.hover + 1.2, function()
        if W.saveTok ~= tok then return end
        TH.tween(lab, { TextTransparency = 1 }, 0.3, "out")
        task.delay(0.3, function()
          if W.saveTok ~= tok then return end
          tk.Visible = false
          lab.Position = UD2(0, 0, 0, 0)
          lab.Text = T("ws.autosave")
          lab.TextColor3 = C.FAINT
          TH.tween(lab, { TextTransparency = 0 }, 0.3, "out")
        end)
      end)
    elseif state == "fail" then
      tk.Visible = false
      lab.Position = UD2(0, 0, 0, 0)
      lab.Text = T("ws.saveFail")
      lab.TextColor3 = C.WARN
      lab.TextTransparency = 0
    else
      tk.Visible = false
      lab.Position = UD2(0, 0, 0, 0)
      lab.Text = T("ws.autosave")
      lab.TextColor3 = C.FAINT
      lab.TextTransparency = 0
    end
  end
  -- 页发了一次存：check() → 服务器回的存档里是不是这一套；retry() → 再发一次。4 秒没回：没存上
  function ws.saving(check, retry)
    W.save = { t = os.clock(), check = check, retry = retry }
    W.saveFail = nil
  end
  local function placeSave()   -- 保存状态挪到车名右边（车名多宽按字估：标题字重的英文、数字宽一点）
    if not (ui.save and ui.name) then return end
    local w = K.textW(ui.name.Text, ui.name.TextSize, false, true)
    ui.save.Position = UD2(0, ui.nx + math.floor(w + 16), 0, compact and 1 or -1)
  end

  ---------------------------------------------------------------- 页签

  local TABS_AIR = { "arms", "mods", "crew", "info" }   -- 飞机没有涂装（现在只有地面车会上色）：不放这个页签
  local TABS_GROUND = { "ammo", "mods", "crew", "skin", "info" }
  local function buildTabs(air)
    for _, t in pairs(ui.tabs or {}) do t.b:Destroy() end
    if ui.tabLine then ui.tabLine:Destroy() end
    ui.tabs = {}
    local list = air and TABS_AIR or TABS_GROUND
    local n = #list
    local gap = 2
    for i, key in ipairs(list) do
      local b = Instance.new("TextButton")
      b.Name = "Tab_" .. key
      b.Text = T("ws.tab." .. key)
      b.Font = TH.F.bold
      b.TextSize = compact and S.small or S.body
      b.AutoButtonColor = false
      b.BorderSizePixel = 0
      b.BackgroundColor3 = C.TEXT
      b.BackgroundTransparency = 1
      b.TextColor3 = C.MUTE
      b.Size = UD2(0, LAY.TABW, 0, LAY.TABH)
      b.Position = UD2(1, -(n - i) * (LAY.TABW + gap), 1, -1)
      b.AnchorPoint = V2(1, 1)
      b.Parent = ui.head
      TH.corner(b)
      b.MouseEnter:Connect(function() if W.tab ~= key then b.TextColor3 = C.TEXT end end)
      b.MouseLeave:Connect(function() if W.tab ~= key then b.TextColor3 = C.MUTE end end)
      b.Activated:Connect(function() if ws.openTab then ws.openTab(key) end end)
      ui.tabs[key] = { b = b }
    end
    local tw = n * LAY.TABW + (n - 1) * gap
    ui.tabLine = K.frame(ui.head, UD2(0, tw, 0, 1), UD2(1, 0, 1, 0), C.LINE, A.line, V2(1, 1))
    ui.tabLine.Name = "TabLine"
  end
  local function paintTabs()
    for key, t in pairs(ui.tabs or {}) do
      local on = key == W.tab
      t.b.BackgroundColor3 = C.TEXT
      t.b.BackgroundTransparency = on and 0 or 1
      t.b.TextColor3 = on and C.BG or C.MUTE
    end
  end
  -- 现有的面板开着没有 / 关上
  local function panelOpen(p)
    if p == "mods" then return G.modsGui ~= nil and G.modsGui.Visible end
    if p == "crew" then return G.crewGui ~= nil and G.crewGui.Visible end
    if p == "info" then return G.infoGui ~= nil and G.infoGui.Visible end
    if p == "ammo" then return G.ammoPanelOpen ~= nil and G.ammoPanelOpen() == true end
    if p == "skin" then
      local g = me.PlayerGui:FindFirstChild("WtSkin")
      return g ~= nil and g.Enabled
    end
    return false
  end
  local function closePanel()
    local p = W.panel
    W.panel = nil
    if p == "mods" and G.modsGui then G.modsGui.Visible = false
    elseif p == "crew" and G.crewGui then G.crewGui.Visible = false
    elseif p == "info" and G.infoGui then G.infoGui.Visible = false
    elseif p == "skin" then
      local g = me.PlayerGui:FindFirstChild("WtSkin")
      if g then g.Enabled = false end
    end
  end
  function ws.openTab(key)
    if not W.on then return end
    local it = W.it
    if not (ui.tabs and ui.tabs[key]) then return end
    closePanel()
    if W.page and key == W.page.name then
      W.tab = key
      paintTabs()
      return
    end
    local opened = nil
    if key == "ammo" and G.openAmmo then
      local tree = G.treeState and G.treeState()
      local md = tree and tree.mods and tree.mods[W.key]
      local fx = WM.fx(it, md and md.done)
      G.openAmmo(W.key, fx and fx.ammo)
      opened = "ammo"
    elseif key == "mods" and G.openMods then
      G.openMods(it)
      opened = "mods"
    elseif key == "crew" and G.openCrew then
      local _, _, slot = nil, nil, 1
      if G.hangarSel then _, _, slot = G.hangarSel() end
      G.openCrew(it.nat, slot or 1, W.key)
      opened = "crew"
    elseif key == "skin" and G.openSkin then
      G.openSkin(W.key)
      opened = "skin"
    elseif key == "info" and G.openInfo then
      G.openInfo(it)
      opened = "info"
    end
    if opened then
      W.panel = opened
      W.tab = key
      paintTabs()
    end
  end

  ---------------------------------------------------------------- 进场 / 退场

  local function slideIn(h, dx, dy, show)
    local b = ui.blocks[h]
    h.Visible = show ~= false
    local f = wrap(h)
    f.Position = b.pos + UD2(0, dx, 0, dy)
    f.GroupTransparency = 1
    TH.tween(f, { Position = b.pos, GroupTransparency = 0 }, "panel", "out")
    local tok = {}
    b.tok = tok
    task.delay(TH.T.panel + 0.03, function() if b.tok == tok then unwrap(h) end end)
  end
  local function enter()
    ui.root.Visible = true
    W.leaveTok = nil
    local has = W.page ~= nil
    slideIn(ui.head, 0, -8)
    slideIn(ui.lg, -24, 0, has)
    slideIn(ui.rg, 24, 0, has)
    slideIn(ui.bg, 0, 24, has)
    ws.detailShow(false)
    if ui.hint then
      ui.hint.Visible = has
      ui.hint.TextTransparency = 1
      TH.tween(ui.hint, { TextTransparency = 0 }, "panel", "out", 0.2)
    end
  end
  local function leave(instant)
    if instant then
      for h, b in pairs(ui.blocks) do
        b.tok = nil
        unwrap(h)
      end
      ui.root.Visible = false
      return
    end
    for _, h in ipairs({ ui.head, ui.lg, ui.rg, ui.bg, ui.dg }) do
      local b = ui.blocks[h]
      local f = wrap(h)
      b.tok = nil
      TH.tween(f, { GroupTransparency = 1 }, "out", "out")
    end
    if ui.hint then TH.tween(ui.hint, { TextTransparency = 1 }, "out", "out") end
    local tok = {}
    W.leaveTok = tok
    task.delay(TH.T.out + 0.02, function()
      if W.leaveTok ~= tok or W.on then return end
      for h in pairs(ui.blocks) do unwrap(h) end
      ui.root.Visible = false
    end)
  end

  ---------------------------------------------------------------- 打开 / 关上

  function G.openWorkshop(it, tab)
    if not it and G.hangarSel then it = G.hangarSel() end
    if not it then return false end
    if not built then
      built = build()
      if not built then return false end
    end
    if W.on then
      if W.key == it.key then
        if tab then ws.openTab(tab) end
        return true
      end
      G.closeWorkshop(true)
    end
    local air = it.branch == "air" or it.branch == "heli"
    W.on, W.it, W.key, W.panel, W.page = true, it, it.key, nil, nil
    W.save, W.saveFail = nil, nil
    if G.hangarWsMode then G.hangarWsMode(true) end
    local N = TT.NAT[it.nat] or { name = it.nat, en = it.nat }
    local R0 = TT.RANKS[it.rank] or { roman = tostring(it.rank) }
    ui.name.Text = zh and it.name or it.en
    ui.sub.Text = T("ws.sub", zh and N.name or N.en, R0.roman, TT.brText(it.br))
    placeSave()
    saveUI("idle")
    buildTabs(air)
    if air then
      arms = arms or WsArms.new(G, ws)
      if arms.open(it) then W.page = arms end
    end
    W.tab = W.page and W.page.name or (air and "arms" or "ammo")
    paintTabs()
    enter()
    if not air then ws.openTab("ammo")   -- 地面车（这一轮）：弹药页还是现在的配弹面板
    elseif tab and tab ~= W.tab then ws.openTab(tab) end
    return true
  end
  function G.closeWorkshop(instant)
    if not W.on then return end
    W.on = false
    W.press = nil
    closePanel()
    if W.page then W.page.close(instant) end
    W.page = nil
    leave(instant)
    if G.hangarWsMode then G.hangarWsMode(false, instant) end
    local S2 = ws.Stage
    if S2 then pcall(S2.home, instant and 0 or TH.T.cam) end
  end
  G.workshopOpen = function() return W.on end
  G.wsKit = K   -- 测试用（拖动条这些下一轮弹药页才用上的零件）
  G.workshopState = function() return W, arms and arms.state(), arms end   -- 测试、截图用
  -- 退一层：开着的旧面板 → 页里的一层（选着的挂点、弹出的小菜单……）→ 回机库
  ws.back = function()
    if W.panel then
      closePanel()
      W.tab = W.page and W.page.name or W.tab
      paintTabs()
      return
    end
    if W.page and W.page.esc() then return end
    G.closeWorkshop()
  end
  -- 只在整备里面退一层（3D 空白处点一下：全景时手一滑不该把整备关了）；退了返回 true
  ws.backSoft = function()
    if W.panel then
      ws.back()
      return true
    end
    return W.page ~= nil and W.page.esc() == true
  end
  G.workshopBack = ws.back

  -- 返回、撤销的键：右键、Backspace 退一层；Esc 也认（Roblox 的系统菜单要开 / 关的那一下不算：先看菜单开着没有，等一下再看一次）；Ctrl / ⌘ + Z 撤销
  local function menuOpen()
    local ok, v = pcall(function() return GuiService.MenuIsOpen end)
    return ok and v == true
  end
  local menuClosedAt = -9
  pcall(function() GuiService.MenuClosed:Connect(function() menuClosedAt = os.clock() end) end)
  local function ctrlDown()
    return UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
      or UIS:IsKeyDown(Enum.KeyCode.LeftSuper) or UIS:IsKeyDown(Enum.KeyCode.RightSuper)
  end
  UIS.InputBegan:Connect(function(io, gp)
    if not W.on then return end
    local kc, ut = io.KeyCode, io.UserInputType
    if kc == Enum.KeyCode.Escape then
      if UIS:GetFocusedTextBox() then return end
      if G.settingsGui and G.settingsGui.Enabled then return end
      local wasOpen = menuOpen() or (os.clock() - menuClosedAt < 0.25)
      task.defer(function()
        if not W.on or wasOpen or menuOpen() then return end
        ws.back()
      end)
    elseif kc == Enum.KeyCode.Backspace then
      if gp or UIS:GetFocusedTextBox() then return end
      ws.back()
    elseif kc == Enum.KeyCode.Z then
      if gp or UIS:GetFocusedTextBox() or not ctrlDown() then return end
      if W.page and W.page.undo then W.page.undo() end
    elseif ut == Enum.UserInputType.MouseButton2 then
      if gp then return end
      if G.stageFree and not G.stageFree(io.Position) then return end
      W.rpress = { pos = io.Position, t = os.clock() }
    elseif ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.Touch then
      if gp or not (G.stageFree and G.stageFree(io.Position)) then return end
      W.press = { pos = io.Position, t = os.clock() }
    end
  end)
  -- 松开时才算点：按下到松开挪了不到 6 像素、不到 0.3 秒（拖着转飞机的不算）
  local function tapped(p, io)
    if not p then return false end
    local ok, d = pcall(function() return (Vector2.new(io.Position.X, io.Position.Y) - Vector2.new(p.pos.X, p.pos.Y)).Magnitude end)
    return ok and d < 6 and os.clock() - p.t < 0.3
  end
  UIS.InputEnded:Connect(function(io)
    if not W.on then return end
    local ut = io.UserInputType
    if ut == Enum.UserInputType.MouseButton2 then
      local p = W.rpress
      W.rpress = nil
      if tapped(p, io) then ws.back() end
    elseif ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.Touch then
      local p = W.press
      W.press = nil
      if tapped(p, io) then ws.backSoft() end
    end
  end)

  -- 每帧：机库收起了（出击、观战、开了主菜单）就马上关；旧面板关了回到本页；存了 4 秒服务器没回：没存上；页自己的（3D 标签）
  local function step(dt)
    if not W.on then return end
    if not (G.hangarGui and G.hangarGui.Visible) then
      G.closeWorkshop(true)
      return
    end
    if W.panel and not panelOpen(W.panel) then
      W.panel = nil
      W.tab = W.page and W.page.name or W.tab
      paintTabs()
    end
    if W.save and os.clock() - W.save.t > 4 then
      W.saveFail = W.save
      W.save = nil
      saveUI("fail")
    end
    if W.page then W.page.step(dt or 0.016) end
  end
  local function safeStep(dt)
    local ok, err = pcall(step, dt)
    if not ok and G.showError then G.showError("local workshop: " .. tostring(err)) end
  end
  if G.frameConn then G.frameConn("workshop", safeStep) else RunService.RenderStepped:Connect(safeStep) end
  -- 存档变了（服务器推了新的 Tree：存上了、我的方案、改装研究完了）：保存状态、页上跟着刷
  me:GetAttributeChangedSignal("Tree"):Connect(function()
    task.defer(function()
      if not W.on then return end
      local sv = W.save
      if sv and sv.check then
        local ok, yes = pcall(sv.check)
        if ok and yes then
          W.save = nil
          saveUI("ok")
        end
      end
      if W.page and W.page.refresh then W.page.refresh() end
    end)
  end)
  -- 窗口大小变了：底部条按新的宽重排（TechUI 先重算画布）
  pcall(function()
    workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
      task.defer(function() if W.on and W.page and W.page.relayout then W.page.relayout() end end)
    end)
  end)
end

return Workshop
