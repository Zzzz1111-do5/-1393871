-- 全面大战场（客户端）——机库（出击阵容、出击）和研究（科技树）界面（用户 11-25：「从1960到现代的战机和坦克 科技树」「再去做一个中 德 美 日 俄系」
--   「不要让玩家拿枪之类的了 就跟战雷完全一样」；同一天给了两张截图：「一进入游戏的界面给我改成这样」「然后点研究就跳科技树」）
--   机库：没出击的时候（Config.Wt.noInfantry 开着）盖住原来的步兵部署页。背后是 3D 厂房（HangarStage.lua），出击阵容里选中的那一辆停在正中；
--     界面照截图的布局：顶上一排（等级圈 + 经验条、主菜单 / 技能树 / 研究 / 试驾四个括号角按钮、四个方图标键、右上金币）、左边一列国旗选系、
--     右边「乘员」框、底下五个槽位（出击阵容，最多 5 辆）、右下这一局的信息和橙色括号角的「战斗」——出的是选中的那一辆（服务器 Tech.lua deployVeh）
--   研究：一个窗口压在机库上——左边一列国旗，中间横着滚的等级列（I～VII），每条线一行，横线连着前置；格子底边的颜色：买下的绿、研究完没买的蓝、
--     正在研究的黄（带进度）、能研究的白、还没开的暗；没开的等级盖一块暗板（锁、要先研究完上一级的几辆）；点一格右边出详情：
--     年份、战斗等级、研究点、价钱，「研究」「购买」「放进出击阵容」「试驾」「资料卡」；暂借别的型号的写「暂用 某某」
--   存档在服务器（玩家属性 Tree，JSON）；动作发 Act：treeNat / treeResearch / treeBuy / treeLineup / deployVeh
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")

local TechUI = {}

function TechUI.init(G)
  local me = Players.LocalPlayer
  local TT = require(RS:WaitForChild("TechTree"))
  local Config = G.Config
  local VD = require(RS:WaitForChild("VehDefs"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local WM = require(RS:WaitForChild("WtMods"))   -- 每辆车的改装
  local WC = require(RS:WaitForChild("WtCrew"))   -- 乘员
  local WD = require(RS:WaitForChild("WtDamage"))   -- 装甲、穿深（资料卡）
  local BAL = require(RS:WaitForChild("Ballistics"))
  local VM = require(script.Parent:WaitForChild("VehModels"))   -- 装甲查看器里的车模
  local RunService = game:GetService("RunService")
  local zh = G.lang == "zh"
  local function L(a, b) return zh and a or b end
  local function nm(it) return zh and it.name or it.en end
  -- 型号的名字（Lang 的 veh.<型号>；没有就写型号）：暂用 / 同族模型那一行写借的是哪一型
  local function vname(id)
    local t = id and G.T and G.T("veh." .. id)
    return (t and t ~= "veh." .. id) and t or string.upper(tostring(id))
  end
  local RGB = Color3.fromRGB
  local WHITE, DIM, FAINT = Color3.new(1, 1, 1), RGB(150, 156, 160), RGB(96, 102, 106)
  local GOOD, GOLD, BAD = RGB(140, 210, 140), RGB(230, 196, 110), RGB(232, 120, 100)
  local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled

  local tree = { res = {}, own = {}, rp = {}, cur = {}, lineup = {}, nat = "cn", free = {} }
  local function readTree()
    local s = me:GetAttribute("Tree")
    if type(s) ~= "string" then return end
    local ok, t = pcall(function() return Http:JSONDecode(s) end)
    if ok and type(t) == "table" then
      for _, f in ipairs({ "res", "own", "rp", "cur", "lineup", "free" }) do t[f] = (type(t[f]) == "table") and t[f] or {} end
      if not TT.NAT[t.nat] then t.nat = "cn" end
      tree = t
    end
  end
  readTree()
  G.treeState = function() return tree end   -- 测试用
  local function act(...)
    local args = table.pack(...)
    pcall(function() G.R.Act:FireServer(table.unpack(args, 1, args.n)) end)
  end
  local noInf = (Config.Wt or {}).noInfantry == true
  G.hangarActive = function() return noInf and not G.forceInfantry end

  -- 这一系现在的出击阵容（服务器没给就按白送的那几辆）
  local function lineupOf(nat)
    local L0 = tree.lineup[nat]
    if type(L0) == "table" and #L0 > 0 then return L0 end
    local out = {}
    for _, br in ipairs(TT.BRANCHES) do
      for _, it in ipairs(TT.list[nat][br]) do if it.free and #out < 5 then table.insert(out, it.key) end end
    end
    return out
  end
  local function defOf(it) return VD.get(it.play) or AD.get(it.play) end

  ---------------------------------------------------------------- 小零件
  local gui = Instance.new("ScreenGui")
  gui.Name = "TechHangar"   -- 别叫 Hangar：改挂载的编辑器（Hangar.lua）已经用了这个名字
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 12
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling   -- 子零件叠在父零件上面、同级的按 ZIndex（默认的 Global 下，ZIndex 高的面板会盖住自己的内容）
  gui.Parent = me:WaitForChild("PlayerGui")
  local function frame(parent, size, pos, col, tr)
    local f = Instance.new("Frame")
    f.Size, f.Position = size, pos or UDim2.new()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = col or RGB(10, 12, 14), tr or 0, 0
    f.Parent = parent
    return f
  end
  local function text(parent, str, size, pos, ts, col, align)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Size, t.Position = size, pos or UDim2.new()
    t.Font = Enum.Font.GothamMedium
    t.TextSize = ts or 14
    t.TextColor3 = col or WHITE
    t.TextXAlignment = align or Enum.TextXAlignment.Left
    t.TextTruncate = Enum.TextTruncate.AtEnd
    t.Text = str
    t.Parent = parent
    return t
  end
  local function button(parent, str, size, pos, primary)
    local b = Instance.new("TextButton")
    b.Size, b.Position = size, pos or UDim2.new()
    b.BackgroundColor3 = primary and WHITE or RGB(30, 34, 38)
    b.BackgroundTransparency = primary and 0 or 0.15
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.TextColor3 = primary and RGB(10, 10, 10) or WHITE
    b.Text = str
    b.Parent = parent
    local s = Instance.new("UIStroke")
    s.Color, s.Transparency, s.Thickness = RGB(120, 126, 130), primary and 1 or 0.5, 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = b
    return b
  end
  local function clear(f) for _, c in ipairs(f:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end end

  ---------------------------------------------------------------- 机库（用户 11-25 的两张截图：「一进入游戏的界面给我改成这样」）
  --   背后是 3D 厂房（HangarStage.lua），出击阵容里选中的那一辆停在正中；界面压在上面：
  --   顶上一排：等级圈 + 经验条 · 主菜单 / 技能树 / 研究 / 试驾（黑底，左上、右下两个括号角）· 四个方图标键（改装、只看车、帮助、资料卡）· 右上金币
  --   左边一列国旗选系；右边「乘员」框和选中这一辆的资料；底下五个槽位（出击阵容）；右下这一局的信息（阶段、战斗等级、三种模式）和橙色括号角的「战斗」
  -- 整套按 1280 × 720 画，窗口大了小了整体缩放（手机按 1000 × 500）
  local H = { modeBtns = {}, vw = 1280, vh = 720 }   -- 机库界面上要改字、要重排的那些零件；vw × vh 是缩放以后的画布
  local root = frame(gui, UDim2.fromScale(1, 1), nil, nil, 1)
  root.Name = "Root"
  do
    local sc = Instance.new("UIScale")
    sc.Parent = root
    local function fit()
      local c = workspace.CurrentCamera
      local vp = c and c.ViewportSize or Vector2.new(1280, 720)
      local s = math.clamp(math.min(vp.X / (mobile and 1000 or 1280), vp.Y / (mobile and 500 or 720)), 0.4, 2.2)
      sc.Scale = s
      root.Size = UDim2.fromScale(1 / s, 1 / s)
      H.vw, H.vh = vp.X / s, vp.Y / s
    end
    fit()
    local c = workspace.CurrentCamera
    if c then c:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end
  end
  local hangar = frame(root, UDim2.fromScale(1, 1), nil, nil, 1)
  hangar.Name = "Hangar"
  hangar.Visible = false
  G.hangarGui = hangar   -- 测试用
  local M0 = mobile and 14 or 24
  local AMBER = RGB(255, 158, 44)
  local INK = RGB(8, 9, 10)
  local sel = { key = nil }     -- 阵容里选中的那一辆（厂房里停的、「战斗」出的）
  local function round(f)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent = f
    return f
  end
  local function stroke(f, col, tr, th)
    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color, s.Transparency, s.Thickness = col, tr or 0, th or 1
    s.Parent = f
    return s
  end
  -- 括号角：左上、右下各一个「L」（len 长、th 粗、往外探 off）
  local function corners(b, col, len, th, off)
    for i = 1, 2 do
      local tl = i == 1
      local s = tl and 0 or 1
      local h = frame(b, UDim2.new(0, len, 0, th), UDim2.new(s, tl and -off or (off - len), s, tl and -off or (off - th)), col, 0)
      local v = frame(b, UDim2.new(0, th, 0, len), UDim2.new(s, tl and -off or (off - th), s, tl and -off or (off - len)), col, 0)
      h.Name, v.Name = "Corner", "Corner"
    end
  end
  -- 右端斜着切一刀（经验条、金币条）：横向渐变转 25°，到头那一段透明；w × h 是这一条的像素大小
  local function slant(f, w, h)
    local g = f:FindFirstChild("Slant")
    if not g then
      g = Instance.new("UIGradient")
      g.Name = "Slant"
      g.Rotation = 25
      g.Parent = f
    end
    local a, b = w * 0.906, h * 0.423
    local t0 = math.clamp(a / math.max(a + b, 1), 0.03, 0.995)
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(t0 - 0.012, 0),
      NumberSequenceKeypoint.new(t0, 1), NumberSequenceKeypoint.new(1, 1) })
  end
  local function fmtNum(n)
    local s = tostring(math.floor(n or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then out = out:sub(2) end
    return out
  end
  -- 黑底括号角按钮：一行字，或者大字底下一行小的英文
  local function navBtn(parent, label, sub, size, pos, col)
    local b = Instance.new("TextButton")
    b.AutoButtonColor = false
    b.Text = ""
    b.Size, b.Position = size, pos
    b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = INK, 0.06, 0
    b.Parent = parent
    corners(b, col or WHITE, 9, 2, 4)
    local two = sub ~= nil and sub ~= ""
    local t1 = text(b, label, UDim2.new(1, -8, two and 0.56 or 1, 0), UDim2.new(0, 4, two and 0.08 or 0, 0), mobile and 13 or 15, col or WHITE, Enum.TextXAlignment.Center)
    t1.Name = "Label"
    t1.Font = Enum.Font.GothamBold
    if two then
      local t2 = text(b, sub, UDim2.new(1, -8, 0.3, 0), UDim2.new(0, 4, 0.62, 0), 8, DIM, Enum.TextXAlignment.Center)
      t2.Name = "Sub"
    end
    b.MouseEnter:Connect(function() b.BackgroundColor3 = RGB(40, 44, 48) end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = INK end)
    return b, t1
  end
  -- 国旗（画的：条纹、圆、星），w × h 像素
  local function flag(parent, nat, w, h)
    local f = frame(parent, UDim2.new(0, w, 0, h), nil, RGB(242, 242, 242), 0)
    f.Name = "Flag"
    f.ClipsDescendants = true
    local function stripes(cols)
      for i, c in ipairs(cols) do frame(f, UDim2.new(1, 0, 1 / #cols, 1), UDim2.new(0, 0, (i - 1) / #cols, 0), c, 0) end
    end
    local function star(sz, x, y)
      local t = text(f, "★", UDim2.new(0, sz * 1.3, 0, sz * 1.3), UDim2.new(0, x - sz * 0.65, 0, y - sz * 0.65), sz, RGB(255, 214, 0), Enum.TextXAlignment.Center)
      t.TextTruncate = Enum.TextTruncate.None
    end
    if nat == "de" then
      stripes({ RGB(18, 18, 18), RGB(206, 32, 38), RGB(248, 198, 0) })
    elseif nat == "ru" then
      stripes({ RGB(244, 244, 244), RGB(0, 58, 166), RGB(214, 44, 32) })
    elseif nat == "jp" then
      local d = math.floor(h * 0.58)
      round(frame(f, UDim2.new(0, d, 0, d), UDim2.new(0.5, -d / 2, 0.5, -d / 2), RGB(190, 0, 40), 0))
    elseif nat == "us" then
      local cols = {}
      for i = 1, 7 do cols[i] = (i % 2 == 1) and RGB(180, 36, 52) or RGB(244, 244, 244) end
      stripes(cols)
      local canton = frame(f, UDim2.new(0, math.floor(w * 0.44), 0, math.floor(h * 4 / 7) + 1), nil, RGB(42, 58, 116), 0)
      for r = 0, 2 do
        for c = 0, 3 do round(frame(canton, UDim2.new(0, 2, 0, 2), UDim2.new((c + 0.5) / 4, -1, (r + 0.5) / 3, -1), WHITE, 0)) end
      end
    else   -- cn
      f.BackgroundColor3 = RGB(208, 44, 34)
      star(math.floor(h * 0.44), w * 0.2, h * 0.3)
      for _, p in ipairs({ { 0.38, 0.12 }, { 0.46, 0.26 }, { 0.46, 0.44 }, { 0.38, 0.58 } }) do star(math.max(6, math.floor(h * 0.16)), w * p[1], h * p[2]) end
    end
    return f
  end
  -- 一列国旗（选系）：选中的带括号角，别的压暗；names：旁边写国名
  local function natTiles(col, w, h, gap, cur, onPick, names)
    clear(col)
    for i, nat in ipairs(TT.NATIONS) do
      local N = TT.NAT[nat]
      local on = nat == cur
      local b = Instance.new("TextButton")
      b.Name = "Nat_" .. nat
      b.AutoButtonColor = false
      b.Text = ""
      b.BackgroundTransparency, b.BorderSizePixel = 1, 0
      b.Size, b.Position = UDim2.new(0, w, 0, h), UDim2.new(0, 0, 0, (i - 1) * (h + gap))
      b.Parent = col
      flag(b, nat, w, h)
      if on then
        corners(b, WHITE, 8, 2, 4)
      else
        frame(b, UDim2.fromScale(1, 1), nil, Color3.new(0, 0, 0), 0.5).Name = "Dim"
      end
      if names then
        local t = text(b, zh and N.name or N.en, UDim2.new(0, 110, 0, 16), UDim2.new(1, 10, 0.5, -8), 12, on and WHITE or RGB(186, 190, 194))
        t.Font = on and Enum.Font.GothamBold or Enum.Font.GothamMedium
        t.TextStrokeTransparency = 0.6
      end
      b.MouseButton1Click:Connect(function() onPick(nat) end)
    end
  end

  -- 机库背后的厂房（HangarStage.lua）：按住空白处拖动转着看车、滚轮拉近拉远
  local Stage = nil
  do
    local ok, S2 = pcall(function() return require(script.Parent:WaitForChild("HangarStage", 3)) end)
    if ok and type(S2) == "table" then Stage = S2 end
    -- 点在空白处（没点到按钮、上面也没开着别的窗口）才算拖车；位移自己拿位置算（鼠标没锁定时 Delta 不一定有）
    local dragIo, last = nil, nil
    local function free()
      return hangar.Visible and not ((G.crewGui and G.crewGui.Visible) or (G.modsGui and G.modsGui.Visible)
        or (G.infoGui and G.infoGui.Visible) or (G.treeGui and G.treeGui.Visible))
    end
    UIS.InputBegan:Connect(function(io, gp)
      if gp or not Stage or not free() then return end
      if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
        dragIo, last = io, io.Position
      end
    end)
    UIS.InputEnded:Connect(function(io)
      if io == dragIo or io.UserInputType == Enum.UserInputType.MouseButton1 then dragIo, last = nil, nil end
    end)
    UIS.InputChanged:Connect(function(io, gp)
      if not (Stage and hangar.Visible) then return end
      if io.UserInputType == Enum.UserInputType.MouseWheel then
        if not gp and free() then Stage.zoom(io.Position.Z) end
      elseif last and dragIo and (io == dragIo
        or (io.UserInputType == Enum.UserInputType.MouseMovement and dragIo.UserInputType == Enum.UserInputType.MouseButton1)) then
        local p = io.Position
        Stage.drag(p.X - last.X, p.Y - last.Y)
        last = p
      end
    end)
    -- 上下两条压暗的渐变：字压在 3D 画面上也看得清
    for i = 1, 2 do
      local top = i == 1
      local sh = frame(hangar, UDim2.new(1, 0, 0, top and 150 or 230), UDim2.new(0, 0, top and 0 or 1, top and 0 or -230), Color3.new(0, 0, 0), 0)
      sh.Name = "Shade"
      sh.ZIndex = 0
      local g = Instance.new("UIGradient")
      g.Rotation = 90
      g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, top and 0.35 or 1), NumberSequenceKeypoint.new(1, top and 1 or 0.3) })
      g.Parent = sh
    end
  end
  local ui = frame(hangar, UDim2.fromScale(1, 1), nil, nil, 1)    -- 整套界面（「只看车」时整个藏起来）
  ui.Name = "UI"
  local mid = frame(ui, UDim2.fromScale(1, 1), nil, nil, 1)       -- 中间那一层（国旗、乘员、这一局的信息）：开着研究窗口时让开
  mid.Name = "Mid"
  H.mid = mid

  -- 三种模式（服务器 Tech.lua：准备阶段按票数，开战定住，workspace 属性 WtMode；每人投的票是玩家属性 ModeVote）
  local MODE_NAME = { ab = L("街机", "Arcade"), rb = L("历史", "Realistic"), sb = L("全真", "Simulator") }
  local MODE_DESC = {
    ab = L("看得见的敌人都标出来，飞机直接在空中出生 · 奖励 ×1", "All visible enemies marked, aircraft spawn in the air · rewards ×1"),
    rb = L("只标近处看得见的敌人，飞机从跑道起飞 · 奖励 ×1.3", "Only nearby visible enemies marked, aircraft take off from the runway · rewards ×1.3"),
    sb = L("不标敌人，只能第一人称（瞄准镜、车内、座舱）· 奖励 ×1.6", "No markers, first person only (sights, interior, cockpit) · rewards ×1.6"),
  }
  -- 选中这一辆的乘员（顶上「技能树」、右边「乘员」框）
  local function crewOfSel()
    local keys = lineupOf(tree.nat)
    local i = sel.key and table.find(keys, sel.key)
    if i and G.openCrew then G.openCrew(tree.nat, i, sel.key) end
  end
  -- 「帮助」：怎么玩
  local function toggleHelp()
    if H.help then
      H.help.Visible = not H.help.Visible
      return
    end
    local p = frame(hangar, UDim2.new(0, 560, 0, 306), UDim2.new(0.5, -280, 0.5, -170), RGB(10, 11, 13), 0.04)
    p.Name = "Help"
    p.ZIndex = 20
    p.Active = true
    stroke(p, RGB(110, 114, 118), 0.4, 1)
    corners(p, WHITE, 12, 2, 5)
    local t = text(p, L("怎么玩", "HOW TO PLAY"), UDim2.new(1, -80, 0, 26), UDim2.new(0, 18, 0, 12), 18)
    t.Font = Enum.Font.GothamBold
    local x = button(p, "×", UDim2.new(0, 32, 0, 28), UDim2.new(1, -44, 0, 10))
    x.MouseButton1Click:Connect(function() p.Visible = false end)
    local lines = {
      L("「研究」开科技树：打仗挣研究点，研究完用金币买下，再放进出击阵容（最多 5 辆）。", "RESEARCH opens the tech tree: earn research points in battle, buy researched vehicles with coins, then add them to your lineup (up to 5)."),
      L("底下选一辆，点「战斗」（或卡片上的「出击」）：直接坐在车里 / 飞机里出现在自己基地；车没了回到这里。", "Pick a slot and press TO BATTLE (or Deploy on the card): you spawn inside it at your base. Lose it and you come back here."),
      L("准备阶段第一辆免费；开战以后出车要出击点（SP），打得好挣得多。每辆车有一次备用。", "The first vehicle is free during preparation; after that deploying costs spawn points (SP) earned in battle. Each vehicle has one backup."),
      L("「技能树」给这一位的乘员加点；齿轮是这辆车的改装；「试驾」随便哪一辆都能开出去试；「i」看资料卡和装甲。", "CREW spends crew skill points; the gear opens this vehicle's modifications; TEST DRIVE works for any vehicle; \"i\" shows stats and armor."),
      L("右下选这一局的模式：街机 / 历史 / 全真（准备阶段按票数定）。左边的国旗换系。", "Bottom right: vote for the mode — Arcade / Realistic / Simulator (decided by votes during preparation). Flags on the left switch nation."),
      L("按住空白处拖动转着看车，滚轮拉近拉远；眼睛图标把界面藏起来只看车。进了车按 F1 看全部按键。", "Drag on empty space to orbit the vehicle, wheel to zoom; the eye icon hides the interface. Press F1 in a vehicle for all keys."),
    }
    for i, s in ipairs(lines) do
      local l = text(p, s, UDim2.new(1, -36, 0, 36), UDim2.new(0, 18, 0, 48 + (i - 1) * 42), 13, RGB(214, 218, 222))
      l.TextWrapped, l.TextTruncate, l.TextYAlignment = true, Enum.TextTruncate.None, Enum.TextYAlignment.Top
    end
    H.help = p
  end

  do   -- 顶上一排
    local TY, TH = mobile and 14 or 28, mobile and 30 or 34
    local LX, XW = mobile and 132 or 176, mobile and 96 or 120
    local NW, NG = mobile and 88 or 106, mobile and 10 or 14
    local IW, IG = mobile and 30 or 34, mobile and 8 or 14
    H.TY, H.TH = TY, TH
    -- 经验条（右端斜的）+ 压在它左头上的等级圈
    local xpBg = frame(ui, UDim2.new(0, XW, 0, 18), UDim2.new(0, LX + 20, 0, TY + (TH - 18) / 2), INK, 0.1)
    xpBg.Name = "Xp"
    slant(xpBg, XW, 18)
    local xpFill = frame(xpBg, UDim2.new(0, 0, 1, 0), nil, RGB(44, 146, 246), 0)
    xpFill.Name = "Fill"
    local xpT = text(xpBg, "", UDim2.new(1, -26, 1, 0), UDim2.new(0, 18, 0, 0), 11, WHITE)
    xpT.Name = "XpT"
    local lv = round(frame(ui, UDim2.new(0, TH, 0, TH), UDim2.new(0, LX, 0, TY), RGB(6, 7, 8), 0))
    lv.Name = "Level"
    stroke(lv, WHITE, 0, 2)
    local lvT = text(lv, "1", UDim2.fromScale(1, 1), nil, mobile and 15 or 18, WHITE, Enum.TextXAlignment.Center)
    lvT.Font = Enum.Font.GothamBold
    H.xpW, H.xpFill, H.xpT, H.lvT = XW, xpFill, xpT, lvT
    -- 四个大键
    local x = LX + 20 + XW + 14
    local navs = {
      { "NavMenu", L("主菜单", "MAIN MENU"), "MENU", function() if G.showMenu then G.showMenu() end end },
      { "NavCrew", L("技能树", "CREW SKILLS"), "CREW", crewOfSel },
      { "NavResearch", L("研究", "RESEARCH"), "RESEARCH", function() if G.openTechTree then G.openTechTree() end end },
      { "NavTest", L("试驾", "TEST DRIVE"), "TEST DRIVE", function() if sel.key then act("testDrive", sel.key) end end },
    }
    for _, n in ipairs(navs) do
      local b = navBtn(ui, n[2], zh and n[3] or nil, UDim2.new(0, NW, 0, TH), UDim2.new(0, x, 0, TY))
      b.Name = n[1]
      b.MouseButton1Click:Connect(n[4])
      x += NW + NG
    end
    -- 四个方图标键（图标是拼的：齿轮、眼睛、圈里的 ? 和 i）；鼠标放上去底下出一行字
    local LIGHT = RGB(222, 224, 226)
    local function gear(b)
      local c = frame(b, UDim2.new(0, 20, 0, 20), UDim2.new(0.5, -10, 0.5, -10), nil, 1)
      for i = 0, 3 do frame(c, UDim2.new(0, 4, 0, 20), UDim2.new(0.5, -2, 0, 0), LIGHT, 0).Rotation = i * 45 end
      round(frame(c, UDim2.new(0, 14, 0, 14), UDim2.new(0.5, -7, 0.5, -7), LIGHT, 0))
      round(frame(c, UDim2.new(0, 6, 0, 6), UDim2.new(0.5, -3, 0.5, -3), INK, 0))
    end
    local function eye(b)
      local c = round(frame(b, UDim2.new(0, 22, 0, 13), UDim2.new(0.5, -11, 0.5, -6.5), nil, 1))
      stroke(c, LIGHT, 0, 2)
      round(frame(c, UDim2.new(0, 7, 0, 7), UDim2.new(0.5, -3.5, 0.5, -3.5), LIGHT, 0))
    end
    local function letter(ch)
      return function(b)
        local c = round(frame(b, UDim2.new(0, 20, 0, 20), UDim2.new(0.5, -10, 0.5, -10), nil, 1))
        stroke(c, LIGHT, 0, 2)
        text(c, ch, UDim2.fromScale(1, 1), nil, 14, LIGHT, Enum.TextXAlignment.Center).Font = Enum.Font.GothamBold
      end
    end
    local function selIt() return sel.key and TT.get(sel.key) end
    local icons = {
      { "IcoMods", L("改装", "Modifications"), gear, function() local it = selIt() if it and G.openMods then G.openMods(it) end end },
      { "IcoView", L("只看车", "Hide interface"), eye, function() ui.Visible = false if H.back then H.back.Visible = true end end },
      { "IcoHelp", L("帮助", "Help"), letter("?"), toggleHelp },
      { "IcoInfo", L("资料卡 · 装甲", "Stats · armor"), letter("i"), function() local it = selIt() if it and G.openInfo then G.openInfo(it) end end },
    }
    x += mobile and 2 or 6
    for _, ic in ipairs(icons) do
      local b = Instance.new("TextButton")
      b.Name = ic[1]
      b.AutoButtonColor = false
      b.Text = ""
      b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = INK, 0.06, 0
      b.Size, b.Position = UDim2.new(0, IW, 0, IW), UDim2.new(0, x, 0, TY + (TH - IW) / 2)
      b.Parent = ui
      corners(b, WHITE, 7, 2, 3)
      ic[3](b)
      local tip = text(b, ic[2], UDim2.new(0, 140, 0, 16), UDim2.new(0.5, -70, 1, 9), 11, WHITE, Enum.TextXAlignment.Center)
      tip.Name = "Tip"
      tip.TextStrokeTransparency = 0.4
      tip.Visible = false
      b.MouseEnter:Connect(function() b.BackgroundColor3 = RGB(40, 44, 48) tip.Visible = true end)
      b.MouseLeave:Connect(function() b.BackgroundColor3 = INK tip.Visible = false end)
      b.MouseButton1Click:Connect(ic[4])
      x += IW + IG
    end
    -- 右上：金币
    local CWd = mobile and 112 or 134
    local coin = frame(ui, UDim2.new(0, CWd, 0, 22), UDim2.new(1, -M0 - CWd, 0, TY + (TH - 22) / 2), INK, 0.1)
    coin.Name = "CoinBar"
    slant(coin, CWd, 22)
    local coinT = text(coin, "", UDim2.new(1, -34, 1, 0), UDim2.new(0, 22, 0, 0), 14, WHITE)
    coinT.Name = "Coins"
    local disc = round(frame(ui, UDim2.new(0, 26, 0, 26), UDim2.new(1, -M0 - CWd - 12, 0, TY + (TH - 26) / 2), RGB(226, 172, 48), 0))
    disc.Name = "Coin"
    stroke(disc, RGB(140, 96, 18), 0, 1.5)
    stroke(round(frame(disc, UDim2.new(0, 16, 0, 16), UDim2.new(0.5, -8, 0.5, -8), RGB(246, 204, 92), 0)), RGB(168, 118, 26), 0.2, 1)
    local function coins()
      local c = me:GetAttribute("Coins")
      coinT.Text = (me:GetAttribute("CoinsInf") == true) and "∞" or ((type(c) == "number") and fmtNum(c) or "—")
    end
    me:GetAttributeChangedSignal("Coins"):Connect(coins)
    me:GetAttributeChangedSignal("CoinsInf"):Connect(coins)
    coins()
    -- 「只看车」以后：右上角留一个键把界面叫回来
    local back = navBtn(hangar, L("显示界面", "SHOW INTERFACE"), nil, UDim2.new(0, 130, 0, TH), UDim2.new(1, -M0 - 130, 0, TY))
    back.Name = "Back"
    back.Visible = false
    back.MouseButton1Click:Connect(function() ui.Visible = true back.Visible = false end)
    H.back = back

    -- 左边一列国旗
    local FW, FH, FG = mobile and 44 or 58, mobile and 29 or 38, mobile and 6 or 8
    local FY = TY + TH + (mobile and 16 or 54)
    local natCol = frame(mid, UDim2.new(0, FW, 0, 5 * (FH + FG)), UDim2.new(0, M0, 0, FY), nil, 1)
    natCol.Name = "Nations"
    H.natCol, H.FW, H.FH, H.FG = natCol, FW, FH, FG
    -- 右边：「乘员」框（点开这一位乘员的技能）+ 选中这一辆的名字、等级、乘员、改装
    local cw = mobile and 136 or 160
    local cb = Instance.new("TextButton")
    cb.Name = "CrewBox"
    cb.AutoButtonColor = false
    cb.Text = ""
    cb.BackgroundColor3, cb.BackgroundTransparency, cb.BorderSizePixel = INK, 0.06, 0
    cb.Size, cb.Position = UDim2.new(0, cw, 0, 32), UDim2.new(1, -M0 - cw, 0, FY)
    cb.Parent = mid
    corners(cb, WHITE, 8, 2, 4)
    local cbT = text(cb, "", UDim2.new(1, -40, 1, 0), UDim2.new(0, 12, 0, 0), 13, AMBER)
    cbT.Font = Enum.Font.GothamBlack
    text(cb, "+", UDim2.new(0, 20, 1, 0), UDim2.new(1, -26, 0, 0), 16, WHITE, Enum.TextXAlignment.Center)
    cb.MouseEnter:Connect(function() cb.BackgroundColor3 = RGB(40, 44, 48) end)
    cb.MouseLeave:Connect(function() cb.BackgroundColor3 = INK end)
    cb.MouseButton1Click:Connect(crewOfSel)
    H.crewBoxT = cbT
    local function right(y, ts, col, h)
      local t = text(mid, "", UDim2.new(0, 380, 0, h or 16), UDim2.new(1, -M0 - 380, 0, FY + y), ts, col, Enum.TextXAlignment.Right)
      t.TextStrokeTransparency = 0.55
      return t
    end
    H.selName = right(42, mobile and 18 or 24, WHITE, 28)
    H.selName.Name = "SelName"
    H.selName.Font = Enum.Font.GothamBold
    H.selSub = right(72, 12, RGB(200, 204, 208))
    H.selCrew = right(90, 12, DIM)
    H.selCrew.Name = "CrewT"
    H.selMods = right(107, 12, DIM)
    H.selMods.Name = "ModCount"
    H.selNote = right(124, 11, DIM)
  end

  do   -- 底下：五个槽位（refreshHangar 里填）；右下：这一局的信息 + 「战斗」
    local SW, SG, SH, BM = mobile and 148 or 172, mobile and 8 or 9, mobile and 92 or 104, mobile and 12 or 20
    H.SW, H.SG, H.SH = SW, SG, SH
    local row = frame(ui, UDim2.new(0, 5 * SW + 4 * SG, 0, SH), UDim2.new(0, M0, 1, -BM - SH), nil, 1)
    row.Name = "Slots"
    H.row = row
    H.winBottom = BM + SH + 12   -- 研究窗口的下沿离屏幕底多远（留出这一排槽位）
    local hint = text(mid, L("选一辆点「战斗」：直接坐在车里 / 飞机里出现在自己基地，车没了回到这里。按住空白处拖动转着看车，滚轮缩放。",
      "Pick a slot and press TO BATTLE: you spawn inside it at your base. Drag on empty space to orbit the vehicle, wheel to zoom."),
      UDim2.new(0, 5 * SW + 4 * SG, 0, 16), UDim2.new(0, M0, 1, -BM - SH - 22), 11, RGB(196, 200, 204))
    hint.Name = "Hint"
    hint.TextStrokeTransparency = 0.6
    local BW, BH = mobile and 190 or 250, mobile and 50 or 62
    local bb = Instance.new("TextButton")
    bb.Name = "Battle"
    bb.AutoButtonColor = false
    bb.Text = ""
    bb.BackgroundColor3, bb.BackgroundTransparency, bb.BorderSizePixel = RGB(9, 9, 10), 0.04, 0
    bb.Size, bb.Position = UDim2.new(0, BW, 0, BH), UDim2.new(1, -M0 - BW, 1, -BM - 4 - BH)
    bb.Parent = ui
    corners(bb, AMBER, mobile and 20 or 26, 4, 5)
    local bt = text(bb, L("战斗", "TO BATTLE"), UDim2.new(1, 0, 0, math.floor(BH * 0.6)), UDim2.new(0, 0, 0, math.floor(BH * 0.08)), mobile and 22 or 28, AMBER, Enum.TextXAlignment.Center)
    bt.Font = Enum.Font.GothamBold
    local bs = text(bb, "", UDim2.new(1, -16, 0, 14), UDim2.new(0, 8, 1, -19), 10, DIM, Enum.TextXAlignment.Center)
    bs.Name = "Sub"
    bb.MouseEnter:Connect(function() bb.BackgroundColor3 = RGB(34, 26, 14) end)
    bb.MouseLeave:Connect(function() bb.BackgroundColor3 = RGB(9, 9, 10) end)
    bb.MouseButton1Click:Connect(function()
      if sel.key then act("deployVeh", sel.key) elseif G.openTechTree then G.openTechTree() end
    end)
    H.battleT, H.battleS = bt, bs
    -- 这一局：阶段和时间、战斗等级、三种模式
    local IH = mobile and 76 or 104
    local card = frame(mid, UDim2.new(0, BW, 0, IH), UDim2.new(1, -M0 - BW, 1, -BM - 4 - BH - 14 - IH), RGB(10, 11, 13), 0.2)
    card.Name = "Match"
    stroke(card, RGB(96, 100, 104), 0.6, 1)
    H.phaseT = text(card, "", UDim2.new(1, -16, 0, 18), UDim2.new(0, 8, 0, 6), 13, WHITE)
    H.phaseT.Name = "Phase"
    H.phaseT.Font = Enum.Font.GothamBold
    H.brT = text(card, "", UDim2.new(1, -16, 0, 14), UDim2.new(0, 8, 0, 26), 11, RGB(186, 190, 194))
    H.brT.Name = "Br"
    local bar = frame(card, UDim2.new(1, -16, 0, 22), UDim2.new(0, 8, 0, 46), nil, 1)
    bar.Name = "Modes"
    for i, m in ipairs({ "ab", "rb", "sb" }) do
      local b = button(bar, MODE_NAME[m], UDim2.new(1 / 3, -4, 1, 0), UDim2.new((i - 1) / 3, 2, 0, 0))
      b.Name = "Mode_" .. m
      b.TextSize = 11
      b.MouseButton1Click:Connect(function() act("wtModeVote", m) end)
      H.modeBtns[m] = b
    end
    local mt = text(card, "", UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 0, 73), 10, RGB(160, 166, 170))
    mt.Name = "ModeT"
    mt.TextWrapped, mt.TextYAlignment = true, Enum.TextYAlignment.Top
    mt.Visible = not mobile
    H.modeT = mt
  end
  local function refreshMode()
    local cur = workspace:GetAttribute("WtMode") or "rb"
    if not MODE_NAME[cur] then cur = "rb" end
    local cnt = { ab = 0, rb = 0, sb = 0 }
    for _, pl in ipairs(Players:GetPlayers()) do
      local v = pl:GetAttribute("ModeVote")
      if cnt[v] then cnt[v] += 1 end
    end
    local mine = me:GetAttribute("ModeVote")
    for m, b in pairs(H.modeBtns) do
      local on = m == cur
      b.BackgroundColor3 = on and WHITE or RGB(30, 34, 38)
      b.TextColor3 = on and RGB(10, 10, 10) or WHITE
      b.Text = MODE_NAME[m] .. ((cnt[m] > 0) and ("  " .. cnt[m]) or "") .. ((mine == m) and "  ✓" or "")
    end
    H.modeT.Text = L("本局模式：", "Mode: ") .. MODE_NAME[cur] .. "  ·  " .. MODE_DESC[cur]
  end

  -- 厂房里停哪一辆：出击阵容里选中的（按真车涂装；有原模型的就是原模型）
  local shownKey = nil
  local function showVehicle(it)
    if not (Stage and Stage.active()) then return end
    local key = it and it.key or ""
    if shownKey == key then return end
    shownKey = key
    if not it then
      Stage.put(nil)
      return
    end
    local base = Stage.floorCF()
    local side = (me:GetAttribute("Side") == "def") and "def" or "atk"
    local d = VD.get(it.play)
    if d then
      local ok, M = pcall(VM.build, d, side, nil, TT.paint(it))
      if ok and M and M.model then
        pcall(function()
          VM.pose(M, d)
          for _, x in ipairs(M.parts) do
            local p = x[1]
            if p:IsA("BasePart") then
              p.CFrame = base * p.CFrame
              p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
            end
          end
        end)
        Stage.put(M.model, { L = d.L or 26, W = d.W or 12, H = d.H or 9 })
        return
      end
    else
      local a = AD.get(it.play)
      local okA, AM = pcall(function() return require(script.Parent:WaitForChild("AirModels", 2)) end)
      if a and okA and AM then
        local ok, M = pcall(AM.build, a, side, AD.presetLoad(a))
        if ok and M and M.model then
          pcall(AM.pose, M, base * CFrame.new(0, a.gearH or 6, 0), { gear = 1, thr = 0 }, os.clock())
          Stage.put(M.model, { L = a.L or 50, W = a.W or 36, H = (a.H or 13) + (a.gearH or 0) * 0.5 })
          return
        end
      end
    end
    Stage.put(nil)
  end

  -- 全真模式：只能第一人称——车外的时候坐进车里（这辆车没有内饰就开瞄准镜）；飞机有座舱的坐进座舱
  task.spawn(function()
    while true do
      task.wait(0.5)
      if workspace:GetAttribute("WtMode") == "sb" then
        local d = G.drive
        if d and G.myVeh and not d.sight and not (G.interiorOn and G.interiorOn()) then
          if not (G.interiorEnterSeat and G.interiorEnterSeat()) and G.driveSetSight then pcall(G.driveSetSight, true) end
        end
        if G.fly and not (G.interiorOn and G.interiorOn()) and G.interiorEnterSeat then pcall(G.interiorEnterSeat) end
      end
    end
  end)

  local openTree, closeTree   -- 下面定义
  -- 这一辆这一局出车要什么（照服务器 WtMatch 推的 S.wt：准备阶段、第一辆免费；出过一次的是备用；备用用完、阵容满了不能出）
  local function spState(it)
    local d = defOf(it)
    if not d or not Config.WtCost then return nil end
    local cat = d.cat or (it.branch == "air" and "jet" or "tank")
    local S = G.S
    local w = S and S.wt
    if not w then
      local ok, c = pcall(Config.WtCost, it.play, cat, 0)
      return ok and c and ("SP " .. c) or nil, FAINT
    end
    local n = (w.ln and w.ln[it.key]) or 0
    if n >= 1 + (w.backup or 1) then return L("备用也用完了", "Used up"), BAD end
    if n == 0 and #(w.order or {}) >= (w.max or 5) then return L("这一局阵容满了", "Lineup full"), FAINT end
    local c = 0
    if S.phase == "battle" and not w.free then
      local ok, v = pcall(Config.WtCost, it.play, cat, w.paid or 0)
      c = ok and v or 0
    end
    local txt = (c == 0) and L("免费", "Free") or ("SP " .. c .. " / " .. (w.sp or 0))
    if n >= 1 then txt = txt .. L(" · 备用", " · backup") end
    return txt, (c == 0) and GOOD or ((c <= (w.sp or 0)) and GOLD or BAD)
  end
  -- 这一局的战斗等级（服务器 Tech.lua 写 workspace 属性 WtBr）：能出到 BR + brUp
  local function brCap()
    local rb = workspace:GetAttribute("WtBr")
    if type(rb) ~= "number" then return nil, nil end
    return rb, rb + ((Config.Wt or {}).brUp or 1.0)
  end
  ---------------------------------------------------------------- 乘员（WtCrew）：阵容每一位一组乘员，升级给技能点，点技能
  local crewP = frame(root, UDim2.fromScale(1, 1), nil, RGB(2, 3, 4), 0.35)
  crewP.Name = "Crew"
  crewP.Visible = false
  crewP.ZIndex = 10
  G.crewGui = crewP   -- 测试用
  local cCard = frame(crewP, UDim2.new(0, 520, 0, 420), UDim2.fromScale(0.5, 0.5), RGB(12, 14, 17), 0.03)
  cCard.AnchorPoint = Vector2.new(0.5, 0.5)
  local cFit = Instance.new("UISizeConstraint")
  cFit.MaxSize = Vector2.new(520, 420)
  cFit.Parent = cCard
  if mobile then cCard.Size = UDim2.fromScale(0.94, 0.9) end
  local cSt = Instance.new("UIStroke")
  cSt.Color, cSt.Transparency = RGB(90, 96, 100), 0.5
  cSt.Parent = cCard
  local cTitle = text(cCard, "", UDim2.new(1, -140, 0, 28), UDim2.new(0, 18, 0, 14), 19)
  cTitle.Font = Enum.Font.GothamBold
  local cClose = button(cCard, L("关闭", "Close"), UDim2.new(0, 100, 0, 32), UDim2.new(1, -118, 0, 12))
  cClose.MouseButton1Click:Connect(function() crewP.Visible = false end)
  local cLv = text(cCard, "", UDim2.new(1, -36, 0, 18), UDim2.new(0, 18, 0, 50), 13, DIM)
  local cBarBg = frame(cCard, UDim2.new(1, -36, 0, 4), UDim2.new(0, 18, 0, 72), RGB(40, 44, 48), 0)
  local cBar = frame(cBarBg, UDim2.new(0, 0, 1, 0), nil, GOLD, 0)
  local cRows = frame(cCard, UDim2.new(1, -36, 1, -100), UDim2.new(0, 18, 0, 88), nil, 1)
  local crewAt = nil   -- { nat, slot, key }
  local function refreshCrew()
    if not crewAt or not crewP.Visible then return end
    clear(cRows)
    local cs = tree.crew and tree.crew[crewAt.nat] and tree.crew[crewAt.nat][tostring(crewAt.slot)] or { xp = 0, sk = {} }
    local it = TT.get(crewAt.key)
    local lv = WC.level(cs.xp)
    local free = WC.free(cs)
    cTitle.Text = L("阵容第 ", "Slot ") .. crewAt.slot .. L(" 位 · 乘员", " · Crew") .. (it and ("（" .. nm(it) .. "）") or "")
    local a, b = WC.xpFor(lv), WC.xpFor(lv + 1)
    cLv.Text = L("等级 ", "Level ") .. lv .. "   ·   " .. L("经验 ", "XP ") .. math.floor(cs.xp or 0) .. " / " .. b .. "   ·   " .. L("技能点 ", "Points ") .. free
    cBar.Size = UDim2.new(math.clamp(((cs.xp or 0) - a) / math.max(b - a, 1), 0, 1), 0, 1, 0)
    for i, s in ipairs(WC.SKILLS) do
      local y = (i - 1) * 58
      local r = frame(cRows, UDim2.new(1, 0, 0, 52), UDim2.new(0, 0, 0, y), RGB(20, 23, 26), 0.1)
      r.Name = "Sk_" .. s.key
      text(r, zh and s.zh or s.en, UDim2.new(0, 120, 0, 20), UDim2.new(0, 10, 0, 6), 14, WHITE)
      text(r, zh and s.dz or s.de, UDim2.new(0, 200, 0, 16), UDim2.new(0, 10, 0, 28), 11, DIM)
      local cur = (cs.sk and cs.sk[s.key]) or 0
      for p = 1, WC.MAXLV do   -- 5 格：点了的亮
        local pip = frame(r, UDim2.new(0, 18, 0, 8), UDim2.new(1, -230 + (p - 1) * 24, 0.5, -4), (p <= cur) and GOLD or RGB(50, 54, 58), 0)
        pip.Name = "Pip"
      end
      local cost = WC.stepCost(cur + 1)
      local can = cur < WC.MAXLV and free >= cost
      local up = button(r, (cur >= WC.MAXLV) and L("满级", "Max") or ("+ " .. cost), UDim2.new(0, 84, 0, 32), UDim2.new(1, -94, 0.5, -16), can)
      up.Name = "Up"
      if not can then up.TextColor3 = FAINT end
      up.MouseButton1Click:Connect(function() if can then act("crewUp", crewAt.nat, crewAt.slot, s.key) end end)
    end
  end
  local function openCrew(nat, slot, key)
    crewAt = { nat = nat, slot = slot, key = key }
    crewP.Visible = true
    refreshCrew()
  end
  G.openCrew = openCrew

  -- 顶上的等级圈、经验条（服务器每次推状态都刷；金币自己听属性）
  local function refreshTop()
    local mine = (G.S and G.S.me) or {}
    local R = Config.Ranks or { 0 }
    local rk = math.clamp(mine.rank or 1, 1, #R)
    local xp = mine.xp or 0
    local frac = 1
    if rk < #R then
      frac = math.clamp((xp - R[rk]) / math.max(1, R[rk + 1] - R[rk]), 0, 1)
      H.xpT.Text = fmtNum(xp) .. " / " .. fmtNum(R[rk + 1]) .. L(" 经验", " XP")
    else
      H.xpT.Text = fmtNum(xp) .. L(" 经验", " XP")
    end
    H.lvT.Text = tostring(rk)
    local w = math.floor(H.xpW * frac + 0.5)
    H.xpFill.Visible = w >= 6
    if w >= 6 then
      H.xpFill.Size = UDim2.new(0, w, 1, 0)
      slant(H.xpFill, w, 18)
    end
  end

  local function refreshHangar()
    natTiles(H.natCol, H.FW, H.FH, H.FG, tree.nat, function(nat)
      tree.nat = nat
      sel.key = nil
      act("treeNat", nat)
      refreshHangar()
    end, true)
    clear(H.row)
    local keys = lineupOf(tree.nat)
    if not (sel.key and table.find(keys, sel.key)) then sel.key = keys[1] end
    local rb, cap = brCap()
    local SW, SG, SH = H.SW, H.SG, H.SH
    for i = 1, 5 do
      local key = keys[i]
      local it = key and TT.get(key)
      local on = it ~= nil and key == sel.key
      local card = Instance.new("TextButton")
      card.Name = it and ("Line_" .. key) or ("Empty_" .. i)
      card.AutoButtonColor = false
      card.Text = ""
      card.Size, card.Position = UDim2.new(0, SW, 1, 0), UDim2.new(0, (i - 1) * (SW + SG), 0, 0)
      card.BackgroundColor3, card.BackgroundTransparency, card.BorderSizePixel = RGB(13, 14, 16), on and 0.06 or 0.26, 0
      card.Parent = H.row
      stroke(card, on and WHITE or RGB(92, 96, 100), on and 0.2 or 0.6, 1)
      if it then
        local over = cap ~= nil and it.br > cap + 0.05   -- 超出这一局能出的战斗等级：标灰（点了服务器也会说）
        if on then corners(card, WHITE, 10, 2, 4) end
        -- 侧影（HudIcons：原模型正侧面拍的；这一型没有图、或者游戏设置里没开 Image API 就空着）
        local im = Instance.new("ImageLabel")
        im.Name = "Icon"
        im.BackgroundTransparency = 1
        im.Size, im.Position = UDim2.new(1, -28, 0, SH - 62), UDim2.new(0, 14, 0, 12)
        im.ScaleType = Enum.ScaleType.Fit
        im.ImageColor3 = on and RGB(244, 246, 248) or RGB(170, 176, 182)
        im.ImageTransparency = over and 0.55 or 0
        im.Parent = card
        if G.hudIconOn then pcall(G.hudIconOn, im, (VD.get(it.play) and "veh_" or "air_") .. it.play) end
        text(card, tostring(i), UDim2.new(0, 14, 0, 14), UDim2.new(0, 7, 0, 4), 11, FAINT)
        if it.stand then   -- 还没有自己的模型：借的是哪一型写在科技树详情里
          text(card, L("暂用模型", "stand-in"), UDim2.new(0, 70, 0, 14), UDim2.new(0, 20, 0, 4), 10, RGB(200, 170, 90))
        elseif it.model then   -- 性能是自己的，模型借同族的
          text(card, L("同族模型", "family model"), UDim2.new(0, 70, 0, 14), UDim2.new(0, 20, 0, 4), 10, RGB(170, 185, 150))
        end
        local brL = text(card, TT.brText(it.br), UDim2.new(0, 40, 0, 14), UDim2.new(1, -47, 0, 4), 12, over and BAD or (on and WHITE or DIM), Enum.TextXAlignment.Right)
        brL.Name = "Br"
        brL.Font = Enum.Font.GothamBold
        local nmL = text(card, nm(it), UDim2.new(1, -12, 0, 18), UDim2.new(0, 6, 1, -50), mobile and 12 or 14, over and FAINT or WHITE, Enum.TextXAlignment.Center)
        nmL.Name = "VehName"
        nmL.Font = Enum.Font.GothamBold
        local spT, spC = spState(it)
        local go = button(card, over and L("超出本局战斗等级", "Above battle BR") or (L("出击", "Deploy") .. (spT and (" · " .. spT) or "")),
          UDim2.new(1, -12, 0, 24), UDim2.new(0, 6, 1, -30), on and not over)
        go.Name = "Go"
        go.TextSize = 11
        go.TextTruncate = Enum.TextTruncate.AtEnd
        if over then
          go.TextColor3 = BAD
        elseif on then
          go.BackgroundColor3 = AMBER
        elseif spC and spC ~= FAINT then
          go.TextColor3 = spC
        end
        go.MouseButton1Click:Connect(function() act("deployVeh", key) end)
        card.MouseButton1Click:Connect(function()
          if sel.key ~= key then
            sel.key = key
            refreshHangar()
          end
        end)
      else
        text(card, "+", UDim2.new(1, 0, 0, 24), UDim2.new(0, 0, 0.5, -26), 20, FAINT, Enum.TextXAlignment.Center)
        text(card, L("研究载具", "Research vehicles"), UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 0.5, 0), 11, FAINT, Enum.TextXAlignment.Center)
        card.MouseButton1Click:Connect(function() if openTree then openTree() end end)
      end
    end
    -- 右边：选中这一辆
    local it = sel.key and TT.get(sel.key)
    local slotI = it and table.find(keys, sel.key)
    if it then
      local N = TT.NAT[it.nat]
      H.selName.Text = nm(it)
      H.selSub.Text = (zh and N.name or N.en) .. " · " .. L("等级 ", "Rank ") .. TT.RANKS[it.rank].roman .. " · BR " .. TT.brText(it.br) .. " · " .. it.year
      local cs = tree.crew and tree.crew[tree.nat] and tree.crew[tree.nat][tostring(slotI)] or { xp = 0 }
      local cfree = WC.free(cs)
      H.selCrew.Text = L("乘员 ", "Crew level ") .. WC.level(cs.xp) .. L(" 级", "") .. ((cfree > 0) and (" · " .. L("技能点 ", "points ") .. cfree) or "")
      H.selCrew.TextColor3 = (cfree > 0) and GOLD or RGB(186, 190, 194)
      local md = tree.mods and tree.mods[sel.key]
      local nDone, nAll = WM.count(it, md and md.done)
      H.selMods.Text = L("改装 ", "Mods ") .. nDone .. " / " .. nAll
      H.selMods.TextColor3 = (nDone == nAll) and GOOD or RGB(186, 190, 194)
      H.selNote.Text = it.stand and L("暂用模型（借的哪一型见科技树详情）", "stand-in model (see the tech tree)") or (it.model and L("模型暂用同族的，性能是本车的", "family model, own stats") or "")
      H.selNote.TextColor3 = it.stand and RGB(200, 170, 90) or RGB(170, 185, 150)
      H.crewBoxT.Text = L("乘员 · ", "CREW · ") .. ((it.branch == "air") and L("战机", "AIRCRAFT") or L("坦克", "TANKS"))
    else
      H.selName.Text, H.selSub.Text, H.selCrew.Text, H.selMods.Text, H.selNote.Text = "", "", "", "", ""
      H.crewBoxT.Text = L("乘员", "CREW")
    end
    -- 右下：「战斗」出的就是选中的这一辆
    local over = it ~= nil and cap ~= nil and it.br > cap + 0.05
    local spT = it and spState(it)
    H.battleT.TextColor3 = (it and not over) and AMBER or FAINT
    H.battleS.Text = it and (over and L("超出本局战斗等级", "Above battle BR") or (nm(it) .. (spT and ("  ·  " .. spT) or ""))) or L("先去研究一辆车", "Research a vehicle first")
    H.battleS.TextColor3 = over and BAD or DIM
    H.brT.Text = L("阵容战斗等级 ", "Lineup BR ") .. TT.brText(TT.lineupBr(keys))
      .. (rb and (L(" · 本局 ", " · battle ") .. TT.brText(rb) .. L("（能出到 ", " (up to ") .. TT.brText(cap) .. L("）", ")")) or "")
    showVehicle(it)
  end
  G.refreshLineup = refreshHangar   -- 不叫 G.refreshHangar：Hangar.lua（改挂载）的刷新函数叫这个名字，顶掉了它就坏了

  -- 原来的部署界面（UI.lua）每次刷新都问一下：该显示部署页的时候机库盖上去
  local lastSig = nil
  function G.hangarSet(show)
    local want = show and G.hangarActive()
    if hangar.Visible ~= want then
      hangar.Visible = want
      if Stage then
        shownKey = nil
        if want then
          Stage.show(true)
        else
          -- 镜头已经有人接手了（坐进了车 / 飞机、开了主菜单）：别动它
          Stage.show(false, G.drive ~= nil or G.fly ~= nil or (G.menuShown ~= nil and G.menuShown() == true))
          Stage.put(nil)
        end
      end
      if want then
        refreshHangar()
      elseif closeTree then
        closeTree()
      end
    end
    if want then
      refreshMode()
      refreshTop()
      local S = G.S
      if S then
        local fmt = function(s) s = math.max(0, math.floor(s or 0)) return string.format("%d:%02d", s // 60, s % 60) end
        H.phaseT.Text = (S.phase == "prep") and (L("准备阶段 ", "Preparing ") .. fmt(S.left)) or (L("剩余时间 ", "Time left ") .. fmt(S.left))
        -- 这一局的账（SP、免费那一辆、出过几次）、战斗等级变了：卡片上的「免费 / SP / 备用 / 用完」跟着刷新
        local w = S.wt or {}
        local sig = table.concat({ tostring(S.phase), tostring(w.sp), tostring(w.free), tostring(w.paid), tostring(#(w.order or {})), tostring(workspace:GetAttribute("WtBr")) }, "|")
        if sig ~= lastSig then
          lastSig = sig
          refreshHangar()
        end
      end
    end
  end
  -- 厂房的镜头每帧摆（坐进车以后镜头归驾驶的）
  do
    local function stepStage(dt)
      if Stage and hangar.Visible and not G.drive then Stage.step(dt or 0.016) end
    end
    if G.frameConn then G.frameConn("hangarStage", stepStage) else RunService.RenderStepped:Connect(stepStage) end
  end

  ---------------------------------------------------------------- 研究（科技树）：用户 11-25 第二张截图——「然后点研究就跳科技树」
  --   一个窗口压在机库上（顶上一排、底下的槽位和「战斗」还露着）：标题「研究 · 国名」、坦克 / 战机、RP、右上 ×；
  --   左边一列国旗换系；中间横着滚的等级列（I～VII），每条线一行，同一级里从左到右是研究顺序，横线连着前置；
  --   格子：类型小字、侧影、名字、战斗等级，底边的颜色是状态（买下的绿、研究完没买的蓝、正在研究的黄带进度、能研究的白、没开的暗）；
  --   还没开的等级盖一块暗板：锁、「先研究 X 级的载具」、已经几辆 / 要几辆；点一格右边出详情（研究、购买、放进阵容、试驾、资料卡）
  local panel = frame(root, UDim2.new(1, -2 * M0, 1, -(H.TY + H.TH + 14) - H.winBottom), UDim2.new(0, M0, 0, H.TY + H.TH + 14), RGB(11, 12, 14), 0.04)
  panel.Name = "TechTree"
  panel.Visible = false
  panel.ZIndex = 5
  panel.Active = true   -- 挡住底下的拖动
  G.treeGui = panel   -- 测试用
  stroke(panel, RGB(100, 104, 108), 0.5, 1)
  local view = { nat = tree.nat, branch = "ground", sel = nil }
  local TV = {}   -- 窗口里要改的零件
  local DW = mobile and 230 or 280   -- 右边详情多宽
  do
    local title = text(panel, L("研究", "RESEARCH"), UDim2.new(0, 110, 0, 26), UDim2.new(0, 16, 0, 8), 18)
    title.Font = Enum.Font.GothamBold
    if zh then text(panel, "RESEARCH", UDim2.new(0, 70, 0, 12), UDim2.new(0, 58, 0, 17), 9, FAINT) end
    TV.natT = text(panel, "", UDim2.new(0, 120, 0, 26), UDim2.new(0, 136, 0, 8), 14, RGB(214, 218, 222))
    TV.natT.Name = "Nation"
    TV.tabs = frame(panel, UDim2.new(0, 180, 0, 26), UDim2.new(0, 262, 0, 8), nil, 1)
    TV.tabs.Name = "Branches"
    local close = Instance.new("TextButton")
    close.Name = "Close"
    close.AutoButtonColor = false
    close.BackgroundTransparency, close.BorderSizePixel = 1, 0
    close.Size, close.Position = UDim2.new(0, 34, 0, 30), UDim2.new(1, -44, 0, 6)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 24
    close.TextColor3 = WHITE
    close.Text = "×"
    close.Parent = panel
    close.MouseEnter:Connect(function() close.TextColor3 = AMBER end)
    close.MouseLeave:Connect(function() close.TextColor3 = WHITE end)
    TV.close = close
    -- RP：圆牌子 + 一格数字（这一系的自由研究点）+ 正在研究哪一辆、攒到多少
    local rx = mobile and 500 or 560
    local badge = round(frame(panel, UDim2.new(0, 22, 0, 22), UDim2.new(1, -rx, 0, 10), nil, 1))
    stroke(badge, WHITE, 0.1, 1.5)
    text(badge, "RP", UDim2.fromScale(1, 1), nil, 9, WHITE, Enum.TextXAlignment.Center).Font = Enum.Font.GothamBold
    local box = frame(panel, UDim2.new(0, 110, 0, 20), UDim2.new(1, -rx + 30, 0, 11), RGB(4, 5, 6), 0.1)
    TV.rpT = text(box, "0", UDim2.new(1, -12, 1, 0), UDim2.new(0, 8, 0, 0), 12, WHITE)
    TV.rpT.Name = "FreeRP"
    TV.curT = text(panel, "", UDim2.new(0, rx - 210, 0, 20), UDim2.new(1, -rx + 150, 0, 11), 12, RGB(190, 194, 198))
    TV.curT.Name = "Current"
    frame(panel, UDim2.new(1, -24, 0, 1), UDim2.new(0, 12, 0, 42), RGB(120, 124, 128), 0.5)
    TV.flags = frame(panel, UDim2.new(0, 60, 0, 240), UDim2.new(0, 12, 0, 54), nil, 1)
    TV.flags.Name = "Nations"
  end
  local scroll = Instance.new("ScrollingFrame")
  scroll.Name = "Tree"
  scroll.Size, scroll.Position = UDim2.new(1, -84 - DW - 24, 1, -64), UDim2.new(0, 84, 0, 52)
  scroll.BackgroundColor3, scroll.BackgroundTransparency, scroll.BorderSizePixel = RGB(6, 7, 8), 0.35, 0
  scroll.ScrollBarThickness = 6
  scroll.ScrollBarImageColor3 = RGB(200, 204, 208)
  scroll.CanvasSize = UDim2.new()
  scroll.Parent = panel
  scroll.InputChanged:Connect(function(io)   -- 只有横向能滚的时候：滚轮横着滚
    if io.UserInputType == Enum.UserInputType.MouseWheel and TV.hOnly then
      scroll.CanvasPosition = Vector2.new(math.max(0, scroll.CanvasPosition.X - io.Position.Z * 90), 0)
    end
  end)
  local detail = Instance.new("ScrollingFrame")
  detail.Name = "Detail"
  detail.Size, detail.Position = UDim2.new(0, DW, 1, -64), UDim2.new(1, -DW - 12, 0, 52)
  detail.BackgroundColor3, detail.BackgroundTransparency, detail.BorderSizePixel = RGB(16, 17, 20), 0.1, 0
  detail.ScrollBarThickness = 4
  detail.ScrollBarImageColor3 = RGB(200, 204, 208)
  detail.CanvasSize = UDim2.new()
  detail.Parent = panel

  local CW, CH = mobile and 116 or 128, mobile and 44 or 50   -- 格宽、格高
  local LBL, PRG, GAPX, PADX, HEADH = 12, 12, 14, 16, 28      -- 格子上面的类型小字、下面的进度字、同一级里两格的间距、每一级两边留的、表头高
  local ROWH = LBL + CH + PRG + 6                              -- 一条线占多高
  local refreshTree
  local function status(it)
    if TT.owned(tree, it.key) then return "own" end
    if TT.researched(tree, it.key) then return "res" end
    if tree.cur[it.nat .. ":" .. it.branch] == it.key then return "cur" end
    if TT.canResearch(tree, it.key) then return "can" end
    return "lock"
  end
  local COL = { own = RGB(28, 46, 34), res = RGB(26, 40, 60), cur = RGB(60, 48, 18), can = RGB(30, 32, 36), lock = RGB(17, 18, 20) }          -- 格子的底色
  local EDGE = { own = RGB(110, 200, 120), res = RGB(96, 156, 232), cur = AMBER, can = RGB(214, 218, 222), lock = RGB(58, 62, 66) }   -- 底边那一道

  ---------------------------------------------------------------- 改装（WtMods）：三列（机动 / 防护 / 火力）× 四级，点一项设成研究目标
  local modsP = frame(root, UDim2.fromScale(1, 1), nil, RGB(2, 3, 4), 0.35)
  modsP.Name = "Mods"
  modsP.Visible = false
  modsP.ZIndex = 10
  G.modsGui = modsP   -- 测试用
  local mCard = frame(modsP, UDim2.fromScale(0.94, 0.86), UDim2.fromScale(0.03, 0.07), RGB(12, 14, 17), 0.03)
  local mLim = Instance.new("UISizeConstraint")
  mLim.MaxSize = Vector2.new(820, 560)
  mLim.Parent = mCard
  mCard.AnchorPoint, mCard.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
  local mStroke = Instance.new("UIStroke")
  mStroke.Color, mStroke.Transparency = RGB(90, 96, 100), 0.5
  mStroke.Parent = mCard
  local mTitle = text(mCard, "", UDim2.new(1, -140, 0, 30), UDim2.new(0, 18, 0, 14), 20)
  mTitle.Font = Enum.Font.GothamBold
  local mSub = text(mCard, "", UDim2.new(1, -36, 0, 18), UDim2.new(0, 18, 0, 46), 12, DIM)
  local mClose = button(mCard, L("关闭", "Close"), UDim2.new(0, 100, 0, 32), UDim2.new(1, -118, 0, 14))
  mClose.Name = "Close"
  mClose.MouseButton1Click:Connect(function() modsP.Visible = false end)
  local mGrid = frame(mCard, UDim2.new(1, -36, 1, -124), UDim2.new(0, 18, 0, 76), nil, 1)
  local mFoot = text(mCard, L("这辆车每打一局，结束时它挣的研究点先给正在研究的那项改装（没选就按顺序自动研究）；研究完自动装上。每一级研究完两项，开下一级。",
    "Research points this vehicle earns go to the selected modification (or the next one in order); researched mods install automatically. Two per tier unlock the next tier."),
    UDim2.new(1, -36, 0, 34), UDim2.new(0, 18, 1, -44), 12, FAINT)
  mFoot.TextWrapped, mFoot.TextTruncate = true, Enum.TextTruncate.None
  local modsIt = nil
  local function refreshMods()
    local it = modsIt
    if not it or not modsP.Visible then return end
    clear(mGrid)
    local md = (tree.mods and tree.mods[it.key]) or {}
    local done = md.done or {}
    local nDone, nAll = WM.count(it, done)
    mTitle.Text = nm(it) .. L("  ·  改装", "  ·  Modifications")
    mSub.Text = L("已装 ", "Installed ") .. nDone .. " / " .. nAll .. (md.cur and (L("   ·   正在研究：", "   ·   Researching: ") .. ((WM.get(it, md.cur) or {})[zh and "zh" or "en"] or "")) or "")
    local classes = {}
    for _, c in ipairs(WM.CLS) do
      for _, m in ipairs(WM.list(it)) do if m.cls == c then classes[c] = true end end
    end
    local cols = {}
    for _, c in ipairs(WM.CLS) do if classes[c] then table.insert(cols, c) end end
    local nC = #cols
    local headH, rowGap, colGap, tierW = 24, 8, 10, 34
    -- 左边 tierW 像素是等级栏，上面 headH 像素是表头；其余按比例分：横坐标比例 sx → 位置 (sx, tierW·(1 − sx))，纵坐标比例 sy → (sy, headH·(1 − sy))
    local function px(sx) return sx, tierW * (1 - sx) end
    local function py(sy) return sy, headH * (1 - sy) end
    for ci, c in ipairs(cols) do   -- 表头：机动 / 防护 / 火力
      local sx, ox = px((ci - 1) / nC)
      local h = text(mGrid, L(WM.CLS_NAME[c][1], WM.CLS_NAME[c][2]), UDim2.new(1 / nC, -colGap - tierW / nC, 0, headH),
        UDim2.new(sx, ox, 0, 0), 13, DIM, Enum.TextXAlignment.Center)
      h.Font = Enum.Font.GothamBold
    end
    for tier = 1, 4 do
      local open = WM.tierOpen(it, done, tier)
      local sy, oy = py((tier - 1) / 4)
      local rl = text(mGrid, ({ "I", "II", "III", "IV" })[tier], UDim2.new(0, tierW, 0.25, -rowGap - headH / 4), UDim2.new(0, 0, sy, oy), 15, open and WHITE or FAINT, Enum.TextXAlignment.Center)
      rl.Font = Enum.Font.GothamBold
      for ci, c in ipairs(cols) do
        local list = {}
        for _, m in ipairs(WM.list(it)) do if m.tier == tier and m.cls == c then table.insert(list, m) end end
        for mi, m in ipairs(list) do
          local isDone, isCur = done[m.key] == true, md.cur == m.key
          local can = WM.canResearch(it, done, m.key)
          local bg = isDone and RGB(38, 74, 50) or (isCur and RGB(104, 84, 30)) or (can and RGB(36, 40, 46)) or RGB(20, 22, 25)
          local w = 1 / nC / #list
          local cell = Instance.new("TextButton")
          cell.Name = "Mod_" .. m.key
          cell.AutoButtonColor = can and not isDone
          cell.Text = ""
          cell.BackgroundColor3, cell.BackgroundTransparency, cell.BorderSizePixel = bg, 0.05, 0
          local sx, ox = px((ci - 1) / nC + (mi - 1) * w)
          cell.Size = UDim2.new(w, -colGap - tierW * w, 0.25, -rowGap - headH / 4)
          cell.Position = UDim2.new(sx, ox, sy, oy)
          cell.Parent = mGrid
          local cs = Instance.new("UIStroke")
          cs.Color = isCur and GOLD or (isDone and GOOD or RGB(70, 76, 80))
          cs.Transparency = (isCur or isDone) and 0.2 or 0.6
          cs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
          cs.Parent = cell
          text(cell, zh and m.zh or m.en, UDim2.new(1, -12, 0, 18), UDim2.new(0, 8, 0, 6), 13, (can or isDone) and WHITE or FAINT)
          local dsc = text(cell, zh and m.dz or m.de, UDim2.new(1, -12, 1, -48), UDim2.new(0, 8, 0, 26), 11, (can or isDone) and DIM or FAINT)
          dsc.TextWrapped, dsc.TextTruncate, dsc.TextYAlignment = true, Enum.TextTruncate.AtEnd, Enum.TextYAlignment.Top
          local cost = WM.cost(it, m)
          local st = isDone and L("已装上", "Installed") or (isCur and (L("研究中 ", "Researching ") .. (md.rp or 0) .. " / " .. cost))
            or (can and (L("点一下研究 · ", "Click to research · ") .. cost)) or (L("还没开 · ", "Locked · ") .. cost)
          text(cell, st, UDim2.new(1, -12, 0, 16), UDim2.new(0, 8, 1, -20), 11, isDone and GOOD or (isCur and GOLD or FAINT)).Name = "State"
          if isCur then   -- 进度条
            local bar = frame(cell, UDim2.new(math.clamp((md.rp or 0) / math.max(cost, 1), 0, 1), 0, 0, 3), UDim2.new(0, 0, 1, -3), GOLD, 0)
            bar.Name = "Bar"
          end
          if can and not isDone then
            cell.MouseButton1Click:Connect(function() act("treeMod", it.key, m.key) end)
          end
        end
      end
    end
  end
  local function openMods(it)
    modsIt = it
    modsP.Visible = true
    refreshMods()
  end
  G.openMods = openMods

  ---------------------------------------------------------------- 资料卡、装甲查看器（详情里「资料卡」）：左边 3D 车模按装甲厚度上色（拖动转、滚轮缩放），
  --   右边性能：极速、炮塔转速 / 俯仰、各处装甲（动能 / 破甲毫米）、主炮每种弹的初速和 0 / 500 / 1000 / 2000 米穿深；飞机写速度、挂载
  local infoP = frame(root, UDim2.fromScale(1, 1), nil, RGB(2, 3, 4), 0.35)
  infoP.Name = "Info"
  infoP.Visible = false
  infoP.ZIndex = 10
  G.infoGui = infoP   -- 测试用
  local iCard = frame(infoP, UDim2.fromScale(0.96, 0.9), UDim2.fromScale(0.5, 0.5), RGB(12, 14, 17), 0.03)
  iCard.AnchorPoint = Vector2.new(0.5, 0.5)
  local iFit = Instance.new("UISizeConstraint")
  iFit.MaxSize = Vector2.new(1060, 640)
  iFit.Parent = iCard
  local iSt = Instance.new("UIStroke")
  iSt.Color, iSt.Transparency = RGB(90, 96, 100), 0.5
  iSt.Parent = iCard
  local iTitle = text(iCard, "", UDim2.new(1, -140, 0, 30), UDim2.new(0, 18, 0, 14), 20)
  iTitle.Font = Enum.Font.GothamBold
  local iSub = text(iCard, "", UDim2.new(1, -150, 0, 18), UDim2.new(0, 18, 0, 46), 12, DIM)
  local iClose = button(iCard, L("关闭", "Close"), UDim2.new(0, 100, 0, 32), UDim2.new(1, -118, 0, 14))
  iClose.MouseButton1Click:Connect(function() infoP.Visible = false end)
  local vp = Instance.new("ViewportFrame")
  vp.Name = "ArmorView"
  vp.Size, vp.Position = UDim2.new(0.56, -24, 1, -138), UDim2.new(0, 18, 0, 74)
  vp.BackgroundColor3, vp.BorderSizePixel = RGB(16, 18, 21), 0
  vp.Ambient, vp.LightColor, vp.LightDirection = RGB(128, 132, 138), RGB(255, 250, 240), Vector3.new(-0.45, -1, -0.55)
  vp.Parent = iCard
  local vcam = Instance.new("Camera")
  vcam.FieldOfView = 38
  vcam.Parent = vp
  vp.CurrentCamera = vcam
  local vpNote = text(vp, "", UDim2.new(1, -20, 0, 18), UDim2.new(0, 10, 1, -26), 12, FAINT)
  -- 图例：装甲厚度 → 颜色
  local RAMP = { { 15, RGB(60, 120, 200) }, { 40, RGB(56, 168, 160) }, { 80, RGB(92, 190, 92) }, { 150, RGB(206, 200, 72) },
    { 300, RGB(232, 150, 52) }, { 600, RGB(222, 72, 52) }, { 1e9, RGB(168, 42, 132) } }
  local function rampCol(mm)
    for _, r in ipairs(RAMP) do if mm <= r[1] then return r[2] end end
    return RAMP[#RAMP][2]
  end
  local legend = frame(iCard, UDim2.new(0.56, -24, 0, 26), UDim2.new(0, 18, 1, -58), nil, 1)
  for i, r in ipairs(RAMP) do
    frame(legend, UDim2.new(1 / #RAMP, -4, 0, 8), UDim2.new((i - 1) / #RAMP, 0, 0, 0), r[2], 0)
    text(legend, (i < #RAMP) and ("≤ " .. r[1]) or "> 600", UDim2.new(1 / #RAMP, -4, 0, 14), UDim2.new((i - 1) / #RAMP, 0, 0, 11), 10, DIM, Enum.TextXAlignment.Center)
  end
  local keBtn = button(iCard, L("对动能弹", "vs KE"), UDim2.new(0, 96, 0, 26), UDim2.new(0, 18, 1, -30), true)
  local ceBtn = button(iCard, L("对破甲弹", "vs HEAT"), UDim2.new(0, 96, 0, 26), UDim2.new(0, 120, 1, -30))
  keBtn.Name, ceBtn.Name = "KE", "CE"
  local stats = Instance.new("ScrollingFrame")
  stats.Name = "Stats"
  stats.Size, stats.Position = UDim2.new(0.44, -18, 1, -90), UDim2.new(0.56, 0, 0, 74)
  stats.BackgroundTransparency, stats.BorderSizePixel, stats.ScrollBarThickness = 1, 0, 5
  stats.CanvasSize = UDim2.new()
  stats.Parent = iCard
  local av = { yaw = math.pi - 0.75, pitch = 0.32, dist = 40, ce = false, it = nil, drag = false }
  -- 一块零件在哪一区：炮塔 / 炮的按炮塔的长宽分正面、侧面（前半截 sf）、后面、顶上；车体按车长车宽分；底下的悬挂、轮子不算
  local function zoneOf(d, tp, grp, pos)
    if grp == "wheel" or grp == "seg" then return nil end
    if grp == "gun" then return "tur", "f" end
    if grp == "turret" or grp == "rws" or grp == "rwg" or grp == "kit" then
      local ts = (d.turret and d.turret.size) or Vector3.new(7, 2, 7)
      local tz, tx = (pos.Z - tp.Z) / math.max(ts.Z / 2, 0.5), (pos.X - tp.X) / math.max(ts.X / 2, 0.5)
      if tz < -0.4 then return "tur", "f" elseif tz > 0.55 then return "tur", "r" elseif math.abs(tx) > 0.6 then return "tur", (tz < 0) and "sf" or "s" end
      return "tur", "t"
    end
    if pos.Y < (d.clear or 1) + 0.6 then return nil end
    local nz, nx = pos.Z / math.max((d.L or 20) / 2, 0.5), pos.X / math.max((d.W or 10) / 2, 0.5)
    if nz < -0.55 then return "hull", "f" elseif nz > 0.6 then return "hull", "r" elseif math.abs(nx) > 0.72 then return "hull", "s" end
    return "hull", "t"
  end
  local function armorMM(prof, zone, face, ce)
    local z = prof[zone] or prof.hull
    local f = z and (z[face] or ((face == "sf") and z.s) or z.f)
    return f and f[ce and 2 or 1] or nil
  end
  local function clearView()
    for _, c in ipairs(vp:GetChildren()) do if c ~= vcam and c ~= vpNote then c:Destroy() end end
  end
  local function buildView(it)
    clearView()
    vpNote.Text = ""
    local d = VD.get(it.play)
    if not d then   -- 飞机：只看外形
      vpNote.Text = L("飞机没有分区装甲：这里只看外形", "Aircraft: no armor zones, shape only")
      local AD2 = AD.get(it.play)
      local okA, AM = pcall(function() return require(script.Parent:WaitForChild("AirModels", 2)) end)
      if AD2 and okA and AM then
        local okB, M = pcall(AM.build, AD2, "atk", AD.presetLoad(AD2))
        if okB and M and M.model then
          pcall(AM.pose, M, CFrame.new(), { gear = 1, thr = 0 }, os.clock())
          M.model.Parent = vp
          av.d = { L = (AD2.hitbox and AD2.hitbox.Z) or 50, W = (AD2.hitbox and AD2.hitbox.X) or 40, H = (AD2.hitbox and AD2.hitbox.Y) or 12 }
          av.dist = math.max(av.d.L, av.d.W) * 1.6
        end
      end
      return
    end
    local okB, M = pcall(VM.build, d, "atk", nil, TT.paint(it))
    if not okB or not M then return end
    local tp = VM.pose(M, d)
    local prof = WD.prof(d)
    for _, x in ipairs(M.parts) do
      local p, grp = x[1], x[2]
      if p:IsA("BasePart") then
        for _, c in ipairs(p:GetChildren()) do
          if c:IsA("SurfaceAppearance") or c:IsA("Decal") or c:IsA("Texture") or c:IsA("ParticleEmitter") or c:IsA("Light") then c:Destroy() end
        end
        pcall(function() p.TextureID = "" end)
        p.Material = Enum.Material.SmoothPlastic
        local zone, face = zoneOf(d, tp, grp, p.CFrame.Position)
        local mm = zone and armorMM(prof, zone, face, av.ce)
        p.Color = mm and rampCol(mm) or RGB(64, 66, 70)
      end
    end
    M.model.Parent = vp
    av.d = d
    av.dist = math.max(d.L or 20, d.W or 10) * 1.75
    vpNote.Text = L("拖动转、滚轮缩放 · 颜色是这一处的装甲厚度", "Drag to rotate, wheel to zoom · color = armor at that spot")
  end
  local function placeCam()
    local d = av.d
    if not d then return end
    local c = Vector3.new(0, (d.H or 6) * 0.45, 0)
    local cp = math.cos(av.pitch)
    local dir = Vector3.new(math.sin(av.yaw) * cp, math.sin(av.pitch), math.cos(av.yaw) * cp)
    vcam.CFrame = CFrame.lookAt(c + dir * av.dist, c)
  end
  vp.InputBegan:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then av.drag = true end
  end)
  vp.InputEnded:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then av.drag = false end
  end)
  vp.InputChanged:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseWheel then
      av.dist = math.clamp(av.dist * (1 - 0.1 * io.Position.Z), 8, 400)
    elseif av.drag and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
      av.yaw -= io.Delta.X * 0.01
      av.pitch = math.clamp(av.pitch + io.Delta.Y * 0.008, -0.2, 1.3)
    end
  end)
  RunService.RenderStepped:Connect(function(dt)
    if not infoP.Visible then return end
    if not av.drag then av.yaw += (dt or 0.016) * 0.22 end   -- 不拖的时候慢慢转
    placeCam()
  end)
  local function statRows(it)
    local rows = {}
    local function add(s, col, ts) table.insert(rows, { s, col or DIM, ts or 13 }) end
    local function T2(k) return G.T and G.T(k) or k end
    if it.stand then add(L("还没有自己的模型：模型和性能暂用 ", "No model yet: model & stats from ") .. vname(it.play), GOLD, 12)
    elseif it.model then add(L("模型暂用同族的 ", "Model borrowed from ") .. vname(it.model) .. L("（性能是本车的）", " (own stats)"), GOLD, 12) end
    local d = VD.get(it.play)
    if d then
      add(L("机动", "Mobility"), WHITE, 15)
      add(L("公路极速 ", "Top speed ") .. math.floor((d.speed or 0) / 2.8 * 3.6 + 0.5) .. " km/h")
      if d.turret then
        local el = d.turret.elev
        add(L("炮塔转速 ", "Turret traverse ") .. (d.turret.trav or 0) .. " °/s   ·   " .. L("俯仰 ", "Elevation ") .. (el and (el[1] .. "° / +" .. el[2] .. "°") or "—"))
      end
      local prof = WD.prof(d)
      add(L("装甲（毫米：对动能弹 / 对破甲弹）", "Armor (mm: vs KE / vs HEAT)"), WHITE, 15)
      for _, f in ipairs({ { "tur", "f", L("炮塔正面", "Turret front") }, { "tur", "s", L("炮塔侧面", "Turret side") }, { "tur", "r", L("炮塔后面", "Turret rear") },
        { "hull", "f", L("车体正面", "Hull front") }, { "hull", "s", L("车体侧面", "Hull side") }, { "hull", "r", L("车体后面", "Hull rear") }, { "hull", "t", L("顶上", "Roof") } }) do
        local z = prof[f[1]]
        local a = z and z[f[2]]
        if a then add(f[3] .. "   " .. a[1] .. " / " .. a[2]) end
      end
      add(L("武器", "Weapons"), WHITE, 15)
      for _, wid in ipairs(d.weapons or {}) do
        add(T2("vw." .. wid), WHITE, 13)
        for _, k in ipairs(BAL.GUN[wid] or {}) do
          local a, pa = BAL.AMMO[k], WD.AMMO[k]
          if a then
            local pens = {}
            for _, m in ipairs({ 0, 500, 1000, 2000 }) do
              local p0 = pa and pa.p0 or 0
              table.insert(pens, math.floor(pa and pa.fall and math.max(p0 * 0.4, p0 - pa.fall * m / 1000) or p0))
            end
            add("   " .. (a.name or k) .. " · " .. (a.v0 or 0) .. " m/s · " .. L("穿深 ", "pen ") .. table.concat(pens, " / ") .. " mm", DIM, 12)
          end
        end
      end
      add(L("（穿深：0 / 500 / 1000 / 2000 米）", "(pen at 0 / 500 / 1000 / 2000 m)"), FAINT, 11)
    else
      local a = AD.get(it.play)
      if a then
        local k = 3.6 / (AD.M or 2.8)
        add(L("性能", "Performance"), WHITE, 15)
        if a.vMax then add(L("最大速度（加力）", "Max speed (AB) ") .. math.floor(a.vMax * k + 0.5) .. " km/h") end
        if a.vMil then add(L("最大速度（军推）", "Max speed (mil) ") .. math.floor(a.vMil * k + 0.5) .. " km/h") end
        if a.stall then add(L("失速速度 ", "Stall speed ") .. math.floor(a.stall * k + 0.5) .. " km/h") end
        add(L("默认挂载", "Default loadout"), WHITE, 15)
        local okG, list = pcall(AD.groups, a, AD.presetLoad(a))
        for _, wid in ipairs(okG and list or {}) do add("   " .. T2("aw." .. wid), DIM, 12) end
      end
    end
    -- 这辆车现在的改装、乘员（买下了才有）
    local md = tree.mods and tree.mods[it.key]
    if TT.owned(tree, it.key) then
      local nDone, nAll = WM.count(it, md and md.done)
      add(L("改装 ", "Modifications ") .. nDone .. " / " .. nAll .. L("（研究完的效果出车时生效）", " (researched ones apply when you deploy)"), GOOD, 12)
    end
    return rows
  end
  local function refreshInfo()
    local it = av.it
    if not it then return end
    iTitle.Text = nm(it) .. L("  ·  资料卡", "  ·  Stats")
    iSub.Text = TT.NAT[it.nat].name .. " · " .. TT.RANKS[it.rank].roman .. " · BR " .. TT.brText(it.br) .. " · " .. it.year
    keBtn.BackgroundColor3, ceBtn.BackgroundColor3 = av.ce and RGB(30, 34, 38) or WHITE, av.ce and WHITE or RGB(30, 34, 38)
    keBtn.TextColor3, ceBtn.TextColor3 = av.ce and WHITE or RGB(10, 10, 10), av.ce and RGB(10, 10, 10) or WHITE
    buildView(it)
    clear(stats)
    local y = 0
    for _, r in ipairs(statRows(it)) do
      local h = r[3] + 8
      local t = text(stats, r[1], UDim2.new(1, -10, 0, h), UDim2.new(0, 0, 0, y), r[3], r[2])
      t.TextWrapped, t.TextTruncate = true, Enum.TextTruncate.None
      y += h + 2
    end
    stats.CanvasSize = UDim2.new(0, 0, 0, y + 10)
  end
  keBtn.MouseButton1Click:Connect(function() av.ce = false refreshInfo() end)
  ceBtn.MouseButton1Click:Connect(function() av.ce = true refreshInfo() end)
  local function openInfo(it)
    av.it = it
    av.yaw, av.pitch = math.pi - 0.75, 0.32
    infoP.Visible = true
    refreshInfo()
  end
  G.openInfo = openInfo

  -- 结算页那一行（WtBattle.lua 结算页里调；服务器 Tech.lua treeAward 写的 t.last）：研究点、倍率、记在哪辆上、改装、乘员经验
  local MODE_NM = { [1] = L("街机", "Arcade") }
  G.treeResultText = function()
    local last = tree and tree.last
    if type(last) ~= "table" or not last.rp then return "" end
    local S = G.S
    if S and S.round and last.n and last.n ~= S.round then return "" end
    local parts = {}
    local mk = last.mk or 1
    table.insert(parts, L("研究点 +", "RP +") .. last.rp .. ((mk ~= 1) and (L("（模式 ×", " (mode ×") .. mk .. L("）", ")")) or ""))
    for _, c in ipairs(last.cur or {}) do
      local it = TT.get(c.k)
      if it then table.insert(parts, nm(it) .. " " .. math.min(c.rp, c.need) .. " / " .. c.need) end
    end
    for k, m in pairs(last.mods or {}) do
      local it = TT.get(k)
      if it then
        local s = nm(it) .. L(" 改装 +", " mods +") .. (m.g or 0)
        local fin = {}
        for _, mkey in ipairs(m.fin or {}) do
          local mm = WM.get(it, mkey)
          if mm then table.insert(fin, zh and mm.zh or mm.en) end
        end
        if #fin > 0 then s ..= L("（研究完：", " (done: ") .. table.concat(fin, L("、", ", ")) .. L("）", ")") end
        table.insert(parts, s)
      end
    end
    local cx = 0
    for _, x in pairs(last.crew or {}) do cx = math.max(cx, x) end
    if cx > 0 then table.insert(parts, L("乘员经验 +", "Crew XP +") .. cx) end
    return table.concat(parts, "   ·   ")
  end

  local function showDetail(it)
    clear(detail)
    local y = 12
    local function line(str, ts, col, h)
      local t = text(detail, str, UDim2.new(1, -24, 0, h or 20), UDim2.new(0, 12, 0, y), ts or 13, col or DIM)
      t.TextWrapped = true
      y += (h or 20) + 4
      return t
    end
    if not it then   -- 没点哪一格：写怎么用、颜色是什么意思
      line(L("点一辆车看详情", "Click a vehicle for details"), 15, WHITE, 22)
      line(L("研究、购买、放进出击阵容、试驾、资料卡都在这里。", "Research, buy, add to lineup, test drive and the stat card are all here."), 12, DIM, 34)
      y += 6
      for _, s in ipairs({ { "own", L("已买下", "Owned") }, { "res", L("已研究，可以买", "Researched — can buy") }, { "cur", L("正在研究", "Researching") },
        { "can", L("可以研究", "Can research") }, { "lock", L("还没开", "Locked") } }) do
        local sw = frame(detail, UDim2.new(0, 26, 0, 14), UDim2.new(0, 12, 0, y + 2), COL[s[1]], 0)
        frame(sw, UDim2.new(1, 0, 0, 2), UDim2.new(0, 0, 1, -2), EDGE[s[1]], 0)
        text(detail, s[2], UDim2.new(1, -60, 0, 18), UDim2.new(0, 48, 0, y), 12, RGB(200, 204, 208))
        y += 22
      end
      detail.CanvasSize = UDim2.new(0, 0, 0, y + 8)
      return
    end
    -- 侧影（有图才占地方）
    local im = Instance.new("ImageLabel")
    im.Name = "Icon"
    im.BackgroundTransparency = 1
    im.Size, im.Position = UDim2.new(1, -40, 0, 54), UDim2.new(0, 20, 0, y)
    im.ScaleType = Enum.ScaleType.Fit
    im.ImageColor3 = RGB(232, 236, 240)
    im.Parent = detail
    local okI, got = pcall(function() return G.hudIconOn and G.hudIconOn(im, (VD.get(it.play) and "veh_" or "air_") .. it.play) end)
    if okI and got then y += 60 else im:Destroy() end
    line(nm(it), 20, WHITE, 26).Font = Enum.Font.GothamBold
    line((zh and it.en or it.name) .. " · " .. it.year, 13, DIM)
    line(L("等级 ", "Rank ") .. TT.RANKS[it.rank].roman .. "（" .. TT.RANKS[it.rank].years .. "）· " .. L("战斗等级 ", "BR ") .. TT.brText(it.br), 13, DIM)
    local stt = status(it)
    local stName = ({ own = L("已买下", "Owned"), res = L("已研究，可以买", "Researched"), cur = L("正在研究", "Researching"),
      can = L("可以研究", "Can research"), lock = L("还没开（先研究前一辆 / 上一级）", "Locked") })[stt]
    line(stName, 14, EDGE[stt] or WHITE)
    if stt ~= "own" and stt ~= "res" then
      line(L("研究点 ", "RP ") .. fmtNum(tree.rp[it.key] or 0) .. " / " .. fmtNum(it.rp), 13, DIM)
    end
    if stt ~= "own" then line(L("价钱 ", "Cost ") .. fmtNum(it.cost) .. L(" 金币", " coins"), 13, DIM) end
    if it.stand then
      local base = it.base and (VD.get(it.base) or AD.get(it.base)) and it.base or "?"
      line(L("还没有自己的模型：暂用 ", "No model yet: uses ") .. vname(base) .. L(" 的模型和性能", "'s model & stats"), 12, RGB(200, 170, 90), 34)
    elseif it.model then
      line(L("模型暂用同族的 ", "Model from ") .. vname(it.model) .. L("；炮、弹、装甲、机动按本车", "; gun, ammo, armour and mobility are its own"), 12, RGB(170, 185, 150), 34)
    end
    y += 8
    local bh = mobile and 32 or 36
    local function btn(str, primary, f)
      local b = button(detail, str, UDim2.new(1, -24, 0, bh), UDim2.new(0, 12, 0, y), primary)
      b.MouseButton1Click:Connect(f)
      y += bh + 8
      return b
    end
    if stt == "can" then
      btn(L("研究这一辆", "Research"), true, function() act("treeResearch", it.key) end).Name = "Research"
    elseif stt == "res" then
      btn(L("购买（", "Buy (") .. fmtNum(it.cost) .. ")", true, function() act("treeBuy", it.key) end).Name = "Buy"
    elseif stt == "own" then
      local L0 = table.clone(lineupOf(it.nat))
      local idx = table.find(L0, it.key)
      if idx then
        btn(L("移出出击阵容", "Remove from lineup"), false, function()
          table.remove(L0, idx)
          act("treeLineup", it.nat, L0)
        end).Name = "LineupOut"
      elseif #L0 < 5 then
        btn(L("放进出击阵容", "Add to lineup"), true, function()
          table.insert(L0, it.key)
          act("treeLineup", it.nat, L0)
        end).Name = "LineupIn"
      else
        line(L("出击阵容满了（5 辆）：先移出一辆", "Lineup full (5)"), 12, DIM)
      end
      local md = tree.mods and tree.mods[it.key]
      local nDone, nAll = WM.count(it, md and md.done)
      btn(L("改装（", "Modifications (") .. nDone .. " / " .. nAll .. L("）", ")"), false, function() openMods(it) end).Name = "ModsBtn"
    end
    -- 试驾：随便哪一辆都能试（服务器 Tech.lua testDrive：东边单独一块场地、三辆靶车、改装全装；下车回机库）
    btn(L("试驾", "Test drive"), false, function()
      if closeTree then closeTree() end
      act("testDrive", it.key)
    end).Name = "TestBtn"
    btn(L("资料卡 · 装甲", "Stats · armor"), false, function() openInfo(it) end).Name = "InfoBtn"
    detail.CanvasSize = UDim2.new(0, 0, 0, y + 8)
  end
  refreshTree = function()
    natTiles(TV.flags, 60, 40, 8, view.nat, function(nat)
      view.nat = nat
      view.sel = nil
      scroll.CanvasPosition = Vector2.new(0, 0)
      refreshTree()
    end, false)
    TV.natT.Text = zh and TT.NAT[view.nat].name or TT.NAT[view.nat].en
    clear(TV.tabs)
    for i, br in ipairs(TT.BRANCHES) do
      local Bn = TT.BRANCH[br]
      local b = button(TV.tabs, zh and Bn.name or Bn.en, UDim2.new(0, 84, 1, 0), UDim2.new(0, (i - 1) * 90, 0, 0), br == view.branch)
      b.Name = "Br_" .. br
      b.TextSize = 13
      b.MouseButton1Click:Connect(function()
        view.branch = br
        view.sel = nil
        scroll.CanvasPosition = Vector2.new(0, 0)
        refreshTree()
      end)
    end
    TV.rpT.Text = fmtNum(tree.free[view.nat] or 0)
    local curKey = tree.cur[view.nat .. ":" .. view.branch]
    local curIt = curKey and TT.get(curKey)
    TV.curT.Text = curIt and (L("正在研究 ", "Researching ") .. nm(curIt) .. "   " .. fmtNum(tree.rp[curKey] or 0) .. " / " .. fmtNum(curIt.rp))
      or L("还没选研究目标：点一辆「可以研究」的", "No research target: pick one you can research")
    clear(scroll)
    local B = TT.BRANCH[view.branch]
    local list = TT.list[view.nat][view.branch]
    -- 每一级多宽：这一级里同一条线最多几辆
    local cnt = {}
    for _, it in ipairs(list) do
      cnt[it.rank] = cnt[it.rank] or {}
      cnt[it.rank][it.col] = (cnt[it.rank][it.col] or 0) + 1
    end
    local colX, colW, x = {}, {}, 0
    for r = 1, #TT.RANKS do
      local m = 1
      for _, n in pairs(cnt[r] or {}) do if n > m then m = n end end
      colX[r], colW[r] = x, 2 * PADX + m * CW + (m - 1) * GAPX
      x += colW[r]
    end
    local rowsH = #B.cols * ROWH
    local totalH = HEADH + rowsH + 6
    -- 表头：等级、年代；每一级之间一道竖线
    for r = 1, #TT.RANKS do
      local open = TT.rankOpen(tree, view.nat, view.branch, r)
      local hd = text(scroll, L("等级 ", "Rank ") .. TT.RANKS[r].roman .. "   " .. TT.RANKS[r].years, UDim2.new(0, colW[r], 0, HEADH - 8), UDim2.new(0, colX[r], 0, 2), 12,
        open and WHITE or DIM, Enum.TextXAlignment.Center)
      hd.Name = "Rank_" .. r
      frame(scroll, UDim2.new(0, colW[r] - 10, 0, 1), UDim2.new(0, colX[r] + 5, 0, HEADH - 5), RGB(120, 124, 128), 0.55)
      if r > 1 then frame(scroll, UDim2.new(0, 1, 0, totalH - 6), UDim2.new(0, colX[r], 0, 3), RGB(120, 124, 128), 0.6) end
    end
    -- 格子
    local used, pos = {}, {}
    for _, it in ipairs(list) do
      used[it.rank] = used[it.rank] or {}
      local k = used[it.rank][it.col] or 0
      used[it.rank][it.col] = k + 1
      local cx = colX[it.rank] + PADX + k * (CW + GAPX)
      local cy = HEADH + (it.col - 1) * ROWH + LBL
      pos[it.key] = { x = cx, y = cy }
      local stt = status(it)
      local lock = stt == "lock"
      local on = view.sel == it.key
      local ct = B.cols[it.col]
      text(scroll, ct and (zh and ct[1] or ct[2]) or "", UDim2.new(0, CW, 0, LBL), UDim2.new(0, cx, 0, cy - LBL), 9, FAINT).Name = "Type"
      local card = Instance.new("TextButton")
      card.Name = "Card_" .. it.key
      card.AutoButtonColor = false
      card.Text = ""
      card.Size, card.Position = UDim2.new(0, CW, 0, CH), UDim2.new(0, cx, 0, cy)
      card.BackgroundColor3, card.BackgroundTransparency, card.BorderSizePixel = COL[stt], 0.04, 0
      card.ZIndex = 2
      card.Parent = scroll
      stroke(card, on and WHITE or RGB(78, 82, 86), on and 0 or 0.5, on and 2 or 1)
      local im = Instance.new("ImageLabel")
      im.Name = "Icon"
      im.BackgroundTransparency = 1
      im.Size, im.Position = UDim2.new(1, -16, 1, -22), UDim2.new(0, 8, 0, 3)
      im.ScaleType = Enum.ScaleType.Fit
      im.ImageColor3 = lock and RGB(124, 128, 132) or RGB(228, 232, 236)
      im.ImageTransparency = lock and 0.5 or 0.05
      im.Parent = card
      if G.hudIconOn then pcall(G.hudIconOn, im, (VD.get(it.play) and "veh_" or "air_") .. it.play) end
      local n1 = text(card, nm(it), UDim2.new(1, -8, 0, 15), UDim2.new(0, 4, 1, -19), 11, lock and RGB(146, 150, 154) or WHITE, Enum.TextXAlignment.Center)
      n1.Font = Enum.Font.GothamBold
      text(card, TT.brText(it.br), UDim2.new(0, 30, 0, 11), UDim2.new(1, -33, 0, 2), 9, DIM, Enum.TextXAlignment.Right)
      if it.stand then
        text(card, L("暂用", "stand-in"), UDim2.new(0, 44, 0, 11), UDim2.new(0, 4, 0, 2), 8, RGB(200, 170, 90))
      elseif it.model then
        text(card, L("同族", "family"), UDim2.new(0, 44, 0, 11), UDim2.new(0, 4, 0, 2), 8, RGB(170, 185, 150))
      end
      -- 底边：状态的颜色；正在研究 / 攒了研究点的是进度条，格子下面写攒了多少
      local rp = tree.rp[it.key] or 0
      local bar = frame(card, UDim2.new(1, 0, 0, 2), UDim2.new(0, 0, 1, -2), EDGE[stt], (stt == "cur" or (rp > 0 and stt ~= "own" and stt ~= "res")) and 0.75 or 0)
      bar.Name = "Edge"
      if stt == "cur" or (rp > 0 and stt ~= "own" and stt ~= "res") then
        frame(bar, UDim2.new(math.clamp(rp / math.max(it.rp, 1), 0, 1), 0, 1, 0), nil, AMBER, 0).Name = "Fill"
        text(scroll, fmtNum(rp) .. " / " .. fmtNum(it.rp), UDim2.new(0, CW, 0, PRG), UDim2.new(0, cx, 0, cy + CH + 2), 9, (stt == "cur") and GOLD or DIM, Enum.TextXAlignment.Center).Name = "Rp"
      end
      card.MouseButton1Click:Connect(function()
        view.sel = it.key
        refreshTree()
      end)
    end
    -- 前置的连线：前一格的右边 → 这一格的左边（同一条线在同一行，横着连；跨着等级的也是一条直线）
    for _, it in ipairs(list) do
      local a, b = it.prev and pos[it.prev], pos[it.key]
      if a and b and b.x > a.x + CW then
        local col = TT.researched(tree, it.prev) and RGB(176, 182, 186) or RGB(72, 76, 80)
        local x0, x1, y0, y1 = a.x + CW, b.x, a.y + CH / 2, b.y + CH / 2
        if math.abs(y1 - y0) < 1 then
          frame(scroll, UDim2.new(0, x1 - x0, 0, 2), UDim2.new(0, x0, 0, y0 - 1), col, 0)
        else   -- 不在同一行：折一下
          local xm = math.floor((x0 + x1) / 2)
          frame(scroll, UDim2.new(0, xm - x0, 0, 2), UDim2.new(0, x0, 0, y0 - 1), col, 0)
          frame(scroll, UDim2.new(0, 2, 0, math.abs(y1 - y0) + 2), UDim2.new(0, xm, 0, math.min(y0, y1) - 1), col, 0)
          frame(scroll, UDim2.new(0, x1 - xm, 0, 2), UDim2.new(0, xm, 0, y1 - 1), col, 0)
        end
      end
    end
    -- 还没开的等级：盖一块暗板，写要先研究完上一级的几辆（底下的格子照样点得到：看详情、试驾）
    for r = 2, #TT.RANKS do
      if not TT.rankOpen(tree, view.nat, view.branch, r) then
        local need = TT.RANK_NEED[r - 1] or 2
        local have = 0
        for _, it in ipairs(list) do
          if it.rank == r - 1 and TT.researched(tree, it.key) then have += 1 end
        end
        local w, h = colW[r] - 12, rowsH - 4
        local ov = frame(scroll, UDim2.new(0, w, 0, h), UDim2.new(0, colX[r] + 6, 0, HEADH + 1), RGB(7, 8, 10), 0.2)
        ov.Name = "Locked_" .. r
        ov.ZIndex = 3
        local mx, my = w / 2, math.max(44, h / 2 - 40)
        local GREY = RGB(96, 100, 106)
        local sh = frame(ov, UDim2.new(0, 30, 0, 40), UDim2.new(0, mx - 15, 0, my - 24), nil, 1)   -- 锁梁
        local shc = Instance.new("UICorner")
        shc.CornerRadius = UDim.new(0, 15)
        shc.Parent = sh
        stroke(sh, GREY, 0, 6)
        local body = frame(ov, UDim2.new(0, 48, 0, 36), UDim2.new(0, mx - 24, 0, my), GREY, 0)   -- 锁体
        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 5)
        bc.Parent = body
        round(frame(body, UDim2.new(0, 9, 0, 9), UDim2.new(0.5, -4.5, 0, 9), RGB(14, 15, 17), 0))
        frame(body, UDim2.new(0, 4, 0, 10), UDim2.new(0.5, -2, 0, 15), RGB(14, 15, 17), 0)
        local t = text(ov, L("先研究 ", "Research more rank ") .. TT.RANKS[r - 1].roman .. L(" 级的载具", " vehicles"), UDim2.new(1, -12, 0, 32), UDim2.new(0, 6, 0, my + 46), 12, WHITE, Enum.TextXAlignment.Center)
        t.TextWrapped, t.TextTruncate = true, Enum.TextTruncate.None
        local cb = frame(ov, UDim2.new(0, 64, 0, 26), UDim2.new(0, mx - 32, 0, my + 82), RGB(30, 33, 38), 0)
        cb.Name = "Count"
        text(cb, have .. " / " .. need, UDim2.fromScale(1, 1), nil, 16, WHITE, Enum.TextXAlignment.Center).Font = Enum.Font.GothamBold
      end
    end
    scroll.CanvasSize = UDim2.new(0, x + 8, 0, totalH)
    TV.hOnly = totalH <= (H.vh or 720) - (H.TY + H.TH + 14) - H.winBottom - 64   -- 竖着不用滚：滚轮横着滚
    showDetail(view.sel and TT.get(view.sel))
  end
  openTree = function()
    view.nat = tree.nat
    panel.Visible = true
    H.mid.Visible = false   -- 机库中间那一层（国旗、乘员、这一局的信息）让开
    refreshTree()
  end
  closeTree = function()
    panel.Visible = false
    H.mid.Visible = true
  end
  TV.close.MouseButton1Click:Connect(closeTree)
  G.openTechTree = openTree
  G.refreshTechTree = function() if panel.Visible then refreshTree() end end

  me:GetAttributeChangedSignal("Tree"):Connect(function()
    readTree()
    if panel.Visible then refreshTree() end
    if modsP.Visible then refreshMods() end
    if crewP.Visible then refreshCrew() end
    if hangar.Visible then refreshHangar() end
  end)
end

return TechUI
