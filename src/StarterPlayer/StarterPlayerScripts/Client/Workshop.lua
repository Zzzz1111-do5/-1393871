-- 全面大战场（客户端）——整备（Workshop）外壳：在机库里给选中的那一辆配挂载 / 弹药、改装、乘员、涂装、看资料
--   用户 11-27：「整个给载具配置武器的系统 做的很粗糙 我需要非常艺术经验的效果 参考战雷」——同类写实军事游戏那种精致、克制、写实的质感，
--   用我们自己的界面美术（docs/style.md、Theme.lua；零件在 WsKit.lua）。舞台就是机库现成的 3D 厂房 / 停机坪（HangarStage），不另开视口；
--   界面和机库同一块 1280 × 720 缩放的画布（TechUI 的 Root）：
--   · 0～92：机库顶栏照旧（「加入战斗」仍是这一屏唯一的主按钮）；「这一局」那块、国旗、乘员框、选中车的资料、阵容卡、科技树把手收起（TechUI G.hangarWsMode）
--   · 抬头 80～120：左边「‹ 机库」、车名（标题 21）、「中国 · VII 级 · BR 13.3」（等宽 13 灰）；右边五个页签「挂载（地面车：弹药）· 改装 · 乘员 · 涂装 · 资料」，
--     选中白底黑字。这一轮只有「挂载」是新做的（WsArms.lua），其余先打开现有的面板（G.openMods / openCrew / openSkin / openInfo / openAmmo），
--     关了回到挂载页；飞机的涂装先不开（现在只有地面车会上色）
--   · 左栏 x 24 宽 300、右栏靠右宽 320（132～580）、底部条 592～696（高 104）；右下角「拖动转 · 滚轮缩放 · Esc 返回」
--   · 进场：两栏从两边滑进 24 像素 + 淡入（CanvasGroup）、底部条从下面上来、抬头往下落一点（0.28 秒先快后慢），镜头飞到全景（0.55 秒两头慢）；
--     退场只淡出（0.18 秒），机库那几层滑回来、镜头回机库的全景
--   · Esc：先关开着的旧面板、退回全景，再按一次回机库；改动即时存（不设「保存」键）
--   手机（1000 × 500 画布）：两栏收窄（236 / 244）、底部条 84 高、挂点卡横着卷、按钮 34 高；选了挂点时左栏只放这个挂点的武器
--   G.openWorkshop(科技树的项, 页签)、G.closeWorkshop(马上)、G.workshopOpen()、G.workshopState()（测试用）
--   入口：机库顶栏的弹药键（飞机 / 直升机；地面车这一轮照旧开配弹面板）
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

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
  -- 排版（Root 画布上的像素）：M 边距、HY / HH 抬头、TOP 两栏的上沿、LW / RW 两栏宽、BH / BM 底部条的高和离下边多远、GAP 间距、DW 悬停资料卡宽
  local LAY = compact and { M = 12, HY = 52, HH = 36, TOP = 96, LW = 236, RW = 244, BH = 84, BM = 10, GAP = 8, DW = 0, TABW = 76, TABH = 34, BACKW = 72 }
    or { M = 24, HY = 80, HH = 40, TOP = 132, LW = 300, RW = 320, BH = 104, BM = 24, GAP = 12, DW = 300, TABW = 96, TABH = 30, BACKW = 80 }

  local W = { on = false, tab = nil, it = nil, key = nil, panel = nil, page = nil }
  local ui = {}
  local built = false
  local H = nil   -- TechUI 的 G.hangarParts（vw × vh 是缩放后的画布、scale 是缩放倍数）
  local ws = { K = K, T = T, LAY = LAY, compact = compact }
  function ws.vw() return (H and H.vw) or 1280 end
  function ws.vh() return (H and H.vh) or 720 end
  function ws.scale() return (H and H.scale) or 1 end
  function ws.colH() return ws.vh() - LAY.TOP - LAY.BM - LAY.BH - LAY.GAP end
  local arms = nil

  ---------------------------------------------------------------- 搭（第一次打开时：TechUI 的机库界面得先搭好）

  local function group(name, size, pos, anchor, z)
    local g = Instance.new("CanvasGroup")
    g.Name = name
    g.BackgroundTransparency = 1
    g.BorderSizePixel = 0
    g.Size, g.Position = size, pos
    g.AnchorPoint = anchor or V2(0, 0)
    g.ZIndex = z or 2
    g.GroupTransparency = 0
    g.Parent = ui.root
    ui.base = ui.base or {}
    ui.base[g] = pos
    return g
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
    -- 3D 标签层（最底下：两栏、底部条压在它上面）
    local lab = K.frame(root, UD2(1, 0, 1, 0), nil, nil, 1)
    lab.Name = "WsLabels"
    lab.ZIndex = 1
    ws.labels = lab
    -- 抬头：「‹ 机库」、车名、国家 · 等级 · BR；右边页签
    local head = group("WsHead", UD2(1, -2 * LAY.M, 0, LAY.HH), UD2(0, LAY.M, 0, LAY.HY), nil, 3)
    ui.head = head
    local back = Instance.new("TextButton")
    back.Name = "WsBack"
    back.Text = ""
    back.AutoButtonColor = false
    back.BackgroundColor3 = C.RAISE
    back.BackgroundTransparency = 0.1
    back.BorderSizePixel = 0
    back.Size = UD2(0, LAY.BACKW, 0, LAY.TABH)
    back.Position = UD2(0, 1, 0.5, 0)
    back.AnchorPoint = V2(0, 0.5)
    back.Parent = head
    TH.corner(back)
    local bst = TH.stroke(back)
    K.chevron(back, 10, LAY.TABH / 2 - 6, 12, C.TEXT)   -- 「‹」画出来（不靠字体）
    K.text(back, T("ws.back"), S.small, "bold", C.TEXT, UD2(1, -28, 1, 0), UD2(0, 26, 0, 0)).Name = "Label"
    back.MouseEnter:Connect(function() TH.tween(bst, { Transparency = A.lineHi }, "hover", "hover") end)
    back.MouseLeave:Connect(function() TH.tween(bst, { Transparency = A.line }, "hover", "hover") end)
    back.Activated:Connect(function() if W.on then G.closeWorkshop() end end)
    local nx = LAY.BACKW + 14
    ui.name = K.text(head, "", compact and S.sub or S.title, "title", C.TEXT, UD2(0, 460, 0, compact and 20 or 24), UD2(0, nx, 0, compact and 0 or -1))
    ui.name.Name = "WsName"
    ui.sub = K.text(head, "", compact and S.tiny or S.small, "mono", C.MUTE, UD2(0, 560, 0, 16), UD2(0, nx, 1, compact and -15 or -15))
    ui.sub.Name = "WsSub"
    ui.flash = K.text(head, "", S.tiny, "bold", C.TEXT, UD2(0, 240, 0, 16), UD2(1, -(5 * (LAY.TABW + 4)) - 10, 0.5, 0), Enum.TextXAlignment.Right, V2(1, 0.5))
    ui.flash.Name = "WsFlash"
    ui.flash.TextTransparency = 1
    -- 左栏、右栏（面板：深色半透明 + 细线；CanvasGroup 外面再大 1 像素，描边不被裁掉）
    local colH = -(LAY.TOP + LAY.BM + LAY.BH + LAY.GAP) + 2
    local lg = group("WsLeft", UD2(0, LAY.LW + 2, 1, colH), UD2(0, LAY.M - 1, 0, LAY.TOP - 1), nil, 2)
    ui.lg = lg
    ws.left = K.panel(lg, UD2(1, -2, 1, -2), UD2(0, 1, 0, 1))
    ws.left.Name = "Panel"
    local rg = group("WsRight", UD2(0, LAY.RW + 2, 1, colH), UD2(1, -LAY.M + 1, 0, LAY.TOP - 1), V2(1, 0), 2)
    ui.rg = rg
    ws.right = K.panel(rg, UD2(1, -2, 1, -2), UD2(0, 1, 0, 1))
    ws.right.Name = "Panel"
    -- 底部条（挂点卡自己是面板，条本身透明）：上下各多 3 像素，卡片悬停抬起、选中的琥珀描边不被裁掉
    local bg = group("WsBottom", UD2(1, -2 * LAY.M + 4, 0, LAY.BH + 6), UD2(0, LAY.M - 2, 1, -LAY.BM + 3), V2(0, 1), 2)
    ui.bg = bg
    local bp = K.frame(bg, UD2(1, -4, 0, LAY.BH), UD2(0, 2, 0, 3), nil, 1)
    bp.Name = "Bar"
    bp.Active = true
    ws.bottom = bp
    -- 悬停资料卡（桌面）：浮在左栏右边
    local dg = group("WsDetail", UD2(0, math.max(LAY.DW, 10) + 2, 0, 212), UD2(0, LAY.M + LAY.LW + LAY.GAP, 0, LAY.TOP), nil, 4)
    dg.Visible = false
    ui.dg = dg
    ws.detail = dg
    -- 右下角的提示（手机不写：没有滚轮、没有 Esc）
    if not compact then
      ui.hint = K.text(root, T("ws.hint"), S.tiny, "body", C.FAINT, UD2(0, 420, 0, 14), UD2(1, -LAY.M, 1, -5), Enum.TextXAlignment.Right, V2(1, 1))
      ui.hint.Name = "WsHint"
    end
    -- 浮在 3D 上的这几块挡住后面的拖车（TechUI：按位置挡）
    G.stageBlockers = G.stageBlockers or {}
    for _, g in ipairs({ head, lg, rg, bg, dg }) do G.stageBlockers[g] = true end
    return true
  end

  ---------------------------------------------------------------- 页签

  local TABS_AIR = { "arms", "mods", "crew", "skin", "info" }
  local TABS_GROUND = { "ammo", "mods", "crew", "skin", "info" }
  local function buildTabs(air)
    for _, t in pairs(ui.tabs or {}) do t.b:Destroy() end
    ui.tabs = {}
    local list = air and TABS_AIR or TABS_GROUND
    local n = #list
    for i, key in ipairs(list) do
      local b = Instance.new("TextButton")
      b.Name = "Tab_" .. key
      b.Text = T("ws.tab." .. key)
      b.Font = TH.F.bold
      b.TextSize = compact and S.small or S.body
      b.AutoButtonColor = false
      b.BorderSizePixel = 0
      b.Size = UD2(0, LAY.TABW, 0, LAY.TABH)
      b.Position = UD2(1, -(n - i) * (LAY.TABW + 4) - 1, 0.5, 0)
      b.AnchorPoint = V2(1, 0.5)
      b.Parent = ui.head
      TH.corner(b)
      local st = TH.stroke(b)
      local off = air and key == "skin"   -- 飞机先不开涂装
      if off then b:SetAttribute("Off", true) end
      local t = { b = b, st = st, off = off }
      b.MouseEnter:Connect(function() if W.tab ~= key and not off then TH.tween(st, { Transparency = A.lineHi }, "hover", "hover") end end)
      b.MouseLeave:Connect(function() if W.tab ~= key and not off then TH.tween(st, { Transparency = A.line }, "hover", "hover") end end)
      b.Activated:Connect(function() if ws.openTab then ws.openTab(key) end end)
      ui.tabs[key] = t
    end
  end
  local function paintTabs()
    for key, t in pairs(ui.tabs or {}) do
      local on = key == W.tab
      TH.setSelected(t.b, on)
      t.st.Transparency = on and 1 or A.line
      if t.off then
        t.b.TextColor3 = C.FAINT
        t.b.BackgroundTransparency = 0.55
      end
    end
  end
  function ws.flash(txt)
    if not ui.flash then return end
    ui.flash.Text = txt or ""
    ui.flash.TextTransparency = 0
    TH.tween(ui.flash, { TextTransparency = 1 }, 0.6, "out", 1.6)
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
    local t = ui.tabs and ui.tabs[key]
    if t and t.off then
      ws.flash(T("ws.skinAir"))
      return
    end
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

  local function enter()
    ui.root.Visible = true
    W.leaveTok = nil
    local function slide(g, dx, dy, show)
      local p = ui.base[g]
      g.Visible = show ~= false
      g.Position = p + UD2(0, dx, 0, dy)
      g.GroupTransparency = 1
      TH.tween(g, { Position = p, GroupTransparency = 0 }, "panel", "out")
    end
    local has = W.page ~= nil
    slide(ui.head, 0, -8)
    slide(ui.lg, -24, 0, has)
    slide(ui.rg, 24, 0, has)
    slide(ui.bg, 0, 24, has)
    ui.dg.Visible = false
    if ui.hint then
      ui.hint.Visible = has
      ui.hint.TextTransparency = 1
      TH.tween(ui.hint, { TextTransparency = 0 }, "panel", "out", 0.2)
    end
  end
  local function leave(instant)
    if instant then
      ui.root.Visible = false
      return
    end
    for _, g in ipairs({ ui.head, ui.lg, ui.rg, ui.bg, ui.dg }) do TH.tween(g, { GroupTransparency = 1 }, "out", "out") end
    if ui.hint then TH.tween(ui.hint, { TextTransparency = 1 }, "out", "out") end
    local tok = {}
    W.leaveTok = tok
    task.delay(TH.T.out + 0.02, function()
      if W.leaveTok == tok and not W.on then ui.root.Visible = false end
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
    if G.hangarWsMode then G.hangarWsMode(true) end
    local N = TT.NAT[it.nat] or { name = it.nat, en = it.nat }
    local R0 = TT.RANKS[it.rank] or { roman = tostring(it.rank) }
    ui.name.Text = zh and it.name or it.en
    ui.sub.Text = T("ws.sub", zh and N.name or N.en, R0.roman, TT.brText(it.br)) .. "   ·   " .. T("ws.autosave")
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
  G.workshopBack = ws.back

  -- Esc：一层层退（开着的旧面板 → 选着的挂点 → 回机库）；输入框有焦点、设置开着时不管
  UIS.InputBegan:Connect(function(io)
    if not W.on or io.KeyCode ~= Enum.KeyCode.Escape then return end
    if UIS:GetFocusedTextBox() then return end
    if G.settingsGui and G.settingsGui.Enabled then return end
    ws.back()
  end)

  -- 每帧：机库收起了（出击、观战、开了主菜单）就马上关；旧面板关了回到本页；页自己的（3D 标签、慢慢转）
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
    if W.page then W.page.step(dt or 0.016) end
  end
  local function safeStep(dt)
    local ok, err = pcall(step, dt)
    if not ok and G.showError then G.showError("local workshop: " .. tostring(err)) end
  end
  if G.frameConn then G.frameConn("workshop", safeStep) else RunService.RenderStepped:Connect(safeStep) end
  -- 存档变了（服务器推了新的 Tree：我的方案、改装研究完了）：页上跟着刷
  me:GetAttributeChangedSignal("Tree"):Connect(function()
    if W.on and W.page and W.page.refresh then task.defer(function() if W.on and W.page then W.page.refresh() end end) end
  end)
  -- 窗口大小变了：底部条按新的宽重排（TechUI 先重算画布）
  pcall(function()
    workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
      task.defer(function() if W.on and W.page and W.page.relayout then W.page.relayout() end end)
    end)
  end)
end

return Workshop
