-- 全面大战场（客户端）——机库（出击阵容、出击）和研究（科技树）界面（用户 11-25：「从1960到现代的战机和坦克 科技树」「再去做一个中 德 美 日 俄系」
--   「不要让玩家拿枪之类的了 就跟战雷完全一样」；同一天给了截图：「一进入游戏的界面给我改成这样」「然后点研究就跳科技树」）
--   机库：没出击的时候（Config.Wt.noInfantry 开着）盖住原来的步兵部署页。背后是 3D 厂房（HangarStage.lua），出击阵容里选中的那一辆停在正中；
--     顶上一排（等级圈 + 经验条、主菜单 / 技能树 / 研究 / 观战四个括号角按钮、改装 / 弹药 / 帮助 / 资料卡四个方图标键、SP、金币）、左边一列国旗选系、
--     右边「乘员」框和选中这一辆的资料、底下五个槽位（出击阵容，点一张选中）、右下这一局的信息和「战斗」——出选中的那一辆（服务器 Tech.lua deployVeh）
--   研究（科技树）：盖在机库上的窗口——左边国旗、等级 I～VII 横排、每列按车种分行、同一行前后连线（前置）；没开的等级整列上锁；
--     格子的颜色：买下的深绿、研究完没买的灰绿、正在研究的琥珀（带进度）、能研究的灰、还没开的暗；点一格右边出详情：
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
  local FMok, FM = pcall(function() return require(RS:WaitForChild("FlightModel", 10)) end)   -- 飞行物理（每型的真实物理量，资料卡上列出来）
  if not FMok then FM = nil end
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
  local TH = G.Theme   -- 统一外观（docs/style.md）
  local WHITE, DIM, FAINT = Color3.new(1, 1, 1), TH.C.MUTE, TH.C.FAINT
  local GOOD, GOLD, BAD = TH.C.GOOD, TH.C.WARN, TH.C.BAD
  local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled

  local tree = { res = {}, own = {}, rp = {}, cur = {}, lineup = {}, nat = "cn", free = {} }
  local function readTree()
    local s = me:GetAttribute("Tree")
    if type(s) ~= "string" then return end
    local ok, t = pcall(function() return Http:JSONDecode(s) end)
    if ok and type(t) == "table" then
      for _, f in ipairs({ "res", "own", "rp", "cur", "lineup", "free", "load", "ammo", "skin", "sets" }) do t[f] = (type(t[f]) == "table") and t[f] or {} end
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
  -- 飞机 / 直升机存的挂载（服务器 Tech.lua treeLoad 收的：tree.load[键] = { p 照哪套预设改的, l 每个挂点, f 内油 }）：
  --   挂载表（同 AD.presetLoad）、预设键、内油；没存过按第一套预设、满内油（同服务器出击）。机库里摆的、资料卡写的、挂载编辑器打开时都按它
  local function airLoad(it)
    local a = it and AD.get(it.play)
    if not a then return nil, nil, 1 end
    local v = tree.load and tree.load[it.key]
    if type(v) == "table" and type(v.l) == "table" then
      return AD.cleanLoad(a, v.l), (type(v.p) == "string") and v.p or nil, AD.cleanFuel(v.f)
    end
    local p = (type(v) == "table" and type(v.p) == "string") and v.p or nil
    return AD.presetLoad(a, p), p or (a.presets and a.presets[1] and a.presets[1].key), (type(v) == "table") and AD.cleanFuel(v.f) or 1
  end
  local function loadSig(load)
    local s = {}
    for i, w in ipairs(load or {}) do s[i] = w or "" end
    return table.concat(s, ",")
  end
  G.treeAirLoad = airLoad   -- 整备的挂载页（WsArms.lua）、测试用
  -- 整备改了挂载（即时存，不设「保存」键）：先改自己这份（机库里摆的、资料卡马上按新的），再发服务器（Tech.lua treeLoad；quiet：不弹「挂载已保存」）
  --   没有预设传 false：中间夹着 nil 的参数表有空洞（同 Depot.lua）
  G.treeSaveLoad = function(key, l, p, f, quiet)
    tree.load = tree.load or {}
    tree.load[key] = { p = p or nil, l = table.clone(l), f = f }
    act("treeLoad", key, l, p or false, f, quiet == true)
  end
  -- 「我的方案」（整备左栏，每一架三个）：存 / 清（l = false）；存档 tree.sets[键]["1"～"3"] = { l, f }（Tech.lua treeLoadSet）
  G.treeSaveSet = function(key, slot, l, f)
    tree.sets = tree.sets or {}
    tree.sets[key] = tree.sets[key] or {}
    tree.sets[key][tostring(slot)] = l and { l = table.clone(l), f = f } or nil
    act("treeLoadSet", key, slot, l or false, f or 1)
  end

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
    t.Font = TH.F.body
    t.TextSize = ts or 14
    t.TextColor3 = col or WHITE
    t.TextXAlignment = align or Enum.TextXAlignment.Left
    t.TextTruncate = Enum.TextTruncate.AtEnd
    t.Text = str
    t.Parent = parent
    return t
  end
  local function button(parent, str, size, pos, primary)   -- 统一外观：主按钮白底黑字，其余灰底白字细边，2 像素圆角（docs/style.md）
    local b = Instance.new("TextButton")
    b.Size, b.Position = size, pos or UDim2.new()
    b.BackgroundColor3 = primary and TH.C.TEXT or TH.C.RAISE
    b.BackgroundTransparency = primary and 0 or 0.1
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Font = TH.F.bold
    b.TextSize = TH.S.body
    b.TextColor3 = primary and TH.C.BG or TH.C.TEXT
    b.Text = str
    b.Parent = parent
    TH.corner(b)
    local s = TH.stroke(b)
    if primary then s.Transparency = 1 end
    return b
  end
  local function clear(f) for _, c in ipairs(f:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end end
  ---------------------------------------------------------------- 机库（D 11-25：用户看了 E 重排的那一版，又发了两张截图——「看最新提交 一进入游戏的界面给我改成这样」）
  --   背后是 3D 厂房（HangarStage.lua），出击阵容里选中的那一辆停在正中，按住空白处拖动转着看、滚轮缩放；界面压在上面，布局照截图：
  --   顶上一排：等级圈 + 经验条 · 主菜单 / 技能树 / 研究 / 观战（黑底，左上、右下两个括号角）· 四个方图标键（改装、弹药、帮助、资料卡）· SP、金币
  --   左上一面现在这一系的小旗（11-25 起换系在科技树里，点小旗打开科技树）；右边「乘员」框、选中这一辆的名字和资料、试驾 / 只看车；底下五个槽位（出击阵容，点一张选中）；
  --   右下这一局的信息（阶段、战斗等级、三种模式）和琥珀色括号角的「战斗」——出选中的那一辆（出不了就灰掉写原因）
  --   颜色、字体照 docs/style.md 从 Theme 取（经验条用绿不用蓝）；整套按 1280 × 720 画，窗口大了小了整体缩放（手机按 1000 × 500）
  local H = { modeBtns = {}, vw = 1280, vh = 720 }   -- 机库界面上要改字、要重排的那些零件；vw × vh 是缩放以后的画布
  local root = frame(gui, UDim2.fromScale(1, 1), nil, nil, 1)
  root.Name = "Root"
  do
    local sc = Instance.new("UIScale")
    sc.Parent = root
    local function fit()
      local c = workspace.CurrentCamera
      local vp = c and c.ViewportSize or Vector2.new(1280, 720)
      local s = math.clamp(math.min(vp.X / (mobile and 1000 or 1280), vp.Y / (mobile and 500 or 720)), 0.4, 2.2) * (G.uiScaleK or 1)   -- 设置里的界面比例
      sc.Scale = s
      root.Size = UDim2.fromScale(1 / s, 1 / s)
      H.vw, H.vh, H.scale = vp.X / s, vp.Y / s, s   -- scale：屏幕像素 ÷ 它 = Root 里的坐标（整备把 HangarStage.toScreen 的点换进来）
    end
    fit()
    G.uiRefit = G.uiRefit or {}
    table.insert(G.uiRefit, fit)
    local c = workspace.CurrentCamera
    if c then c:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end
  end
  local hangar = frame(root, UDim2.fromScale(1, 1), nil, nil, 1)
  hangar.Name = "Hangar"
  hangar.Visible = false
  G.hangarGui = hangar   -- 测试用
  local M0 = mobile and 14 or 24
  local FLAG_W = mobile and 46 or 64
  local AMBER, INK, HOVER = TH.C.WARN, TH.C.BG, TH.C.RAISE
  local function round(f)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent = f
    return f
  end
  local function edge(f, col, tr, th)
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
    corners(b, col or TH.C.TEXT, 9, 2, 4)
    local two = sub ~= nil and sub ~= ""
    local t1 = text(b, label, UDim2.new(1, -8, two and 0.56 or 1, 0), UDim2.new(0, 4, two and 0.08 or 0, 0), mobile and TH.S.small or TH.S.body, col or TH.C.TEXT, Enum.TextXAlignment.Center)
    t1.Name = "Label"
    t1.Font = TH.F.bold
    if two then
      local t2 = text(b, sub, UDim2.new(1, -8, 0.3, 0), UDim2.new(0, 4, 0.62, 0), 8, TH.C.MUTE, Enum.TextXAlignment.Center)
      t2.Name = "Sub"
    end
    b.MouseEnter:Connect(function() b.BackgroundColor3 = HOVER end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = b:GetAttribute("Lit") and HOVER or INK end)
    return b, t1
  end

  -- 国旗：真国旗用色块拼（中国五星红旗、德国黑红金、美国星条旗、日本日章旗、俄罗斯白蓝红）
  local function drawFlag(f, nat)
    f.ClipsDescendants = true
    local function bar(x, y, w, h, c) frame(f, UDim2.fromScale(w, h), UDim2.fromScale(x, y), c, 0) end
    if nat == "cn" then
      bar(0, 0, 1, 1, RGB(222, 41, 16))
      local function star(x, y, s, rot)
        local t = text(f, "★", UDim2.fromScale(s, s * 1.5), UDim2.fromScale(x, y), 10, RGB(255, 222, 0), Enum.TextXAlignment.Center)
        t.TextScaled = true
        t.TextTruncate = Enum.TextTruncate.None
        t.AnchorPoint = Vector2.new(0.5, 0.5)
        t.Rotation = rot or 0
      end
      star(0.17, 0.28, 0.24)
      star(0.34, 0.1, 0.08, 20)
      star(0.41, 0.21, 0.08, 45)
      star(0.41, 0.35, 0.08, 0)
      star(0.34, 0.45, 0.08, 20)
    elseif nat == "de" then
      bar(0, 0, 1, 1 / 3, RGB(0, 0, 0))
      bar(0, 1 / 3, 1, 1 / 3, RGB(221, 0, 0))
      bar(0, 2 / 3, 1, 1 / 3 + 0.01, RGB(255, 206, 0))
    elseif nat == "us" then
      for i = 0, 12 do bar(0, i / 13, 1, 1 / 13 + 0.005, (i % 2 == 0) and RGB(178, 34, 52) or RGB(255, 255, 255)) end
      bar(0, 0, 0.42, 7 / 13, RGB(60, 59, 110))
      -- 星：5 行交错（4、3、4、3、4 颗）一颗颗摆（原来一个三行的字符串 TextScaled，旗子小的时候挤成一团）
      for r = 0, 4 do
        local odd = r % 2 == 1
        for c = 0, odd and 2 or 3 do
          local x = 0.42 * (c + (odd and 1 or 0.5)) / 4
          local y = (7 / 13) * (r + 0.5) / 5
          local t = text(f, "★", UDim2.fromScale(0.42 / 4.4, (7 / 13) / 4.2), UDim2.fromScale(x, y), 6, RGB(255, 255, 255), Enum.TextXAlignment.Center)
          t.TextScaled, t.TextTruncate = true, Enum.TextTruncate.None
          t.AnchorPoint = Vector2.new(0.5, 0.5)
        end
      end
    elseif nat == "jp" then
      bar(0, 0, 1, 1, RGB(250, 250, 250))
      local d = frame(f, UDim2.fromScale(0.36, 0.54), UDim2.fromScale(0.5, 0.5), RGB(188, 0, 45), 0)
      d.AnchorPoint = Vector2.new(0.5, 0.5)
      local ar = Instance.new("UIAspectRatioConstraint")
      ar.AspectRatio = 1
      ar.Parent = d
      local c = Instance.new("UICorner")
      c.CornerRadius = UDim.new(0.5, 0)
      c.Parent = d
    elseif nat == "ru" then
      bar(0, 0, 1, 1 / 3, RGB(255, 255, 255))
      bar(0, 1 / 3, 1, 1 / 3, RGB(0, 57, 166))
      bar(0, 2 / 3, 1, 1 / 3 + 0.01, RGB(213, 43, 30))
    end
  end
  -- 一列国旗按钮（机库左边、研究窗口左边共用）：选中的整面亮、带括号角，别的压暗；按钮名 Nat_<系>
  local function flagStrip(parent, cur, onPick, w)
    clear(parent)
    local lay = parent:FindFirstChildOfClass("UIListLayout")
    if not lay then
      lay = Instance.new("UIListLayout")
      lay.Padding = UDim.new(0, mobile and 6 or 10)
      lay.SortOrder = Enum.SortOrder.LayoutOrder
      lay.Parent = parent
    end
    local fh = math.floor(w * 0.62)
    for i, nat in ipairs(TT.NATIONS) do
      local N = TT.NAT[nat]
      local on = nat == cur
      local b = Instance.new("TextButton")
      b.Name = "Nat_" .. nat
      b.LayoutOrder = i
      b.Text = ""
      b.AutoButtonColor = false
      b.BackgroundTransparency = 1
      b.Size = UDim2.new(0, w, 0, fh + 18)
      b.Parent = parent
      local fl = frame(b, UDim2.new(1, 0, 0, fh), nil, TH.C.BG, 0)
      fl.Name = "Flag"
      drawFlag(fl, nat)
      local dim = frame(fl, UDim2.fromScale(1, 1), nil, TH.C.BG, on and 1 or 0.5)   -- 没选中的压暗
      dim.ZIndex = 3
      if on then
        local br = frame(b, UDim2.new(1, 0, 0, fh), nil, nil, 1)   -- 括号角画在旗子外面（旗子自己裁剪）
        br.Name = "Sel"
        corners(br, TH.C.TEXT, 8, 2, 4)
      end
      local nt = text(b, zh and N.name or N.en, UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 0, fh + 2), TH.S.tiny, on and TH.C.TEXT or TH.C.MUTE, Enum.TextXAlignment.Center)
      nt.TextStrokeTransparency = 0.6
      b.MouseButton1Click:Connect(function() onPick(nat) end)
    end
  end

  -- 机库背后的厂房（HangarStage.lua）：按住空白处拖动转着看车、滚轮拉近拉远
  local Stage = nil
  do
    local ok, S2 = pcall(function() return require(script.Parent:WaitForChild("HangarStage", 3)) end)
    if ok and type(S2) == "table" then Stage = S2 end
    -- 点在空白处（没点到按钮、上面也没开着别的窗口）才算拖车；位移自己拿位置算（鼠标没锁定时 Delta 不一定有）
    --   浮在 3D 上的面板（整备的左右栏、底部条，配弹面板……）多半是不接收点击的 Frame：gp 是 false，只看 gp 的话在面板空白处按住拖动会转后面的车——
    --   登记进 G.stageBlockers（[界面零件] = true）的、看得见的，按位置挡住；面板自己最好也设 Active = true（引擎直接把点击吞掉、gp 为 true）
    G.stageBlockers = G.stageBlockers or {}
    local function shownGui(o)
      local g = o
      while g and g:IsA("GuiObject") do
        if not g.Visible then return false end
        g = g.Parent
      end
      return not (g and g:IsA("LayerCollector") and not g.Enabled)
    end
    local function overBlocker(pos)
      if not pos then return false end
      for o in pairs(G.stageBlockers) do
        local ok, hit = pcall(function()
          if not o.Parent or not shownGui(o) then return false end
          local a, s = o.AbsolutePosition, o.AbsoluteSize
          return pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y
        end)
        if ok and hit then return true end
      end
      return false
    end
    local dragIo, last = nil, nil
    local function free(pos)
      return hangar.Visible and not ((G.crewGui and G.crewGui.Visible) or (G.modsGui and G.modsGui.Visible)
        or (G.infoGui and G.infoGui.Visible) or (G.treeGui and G.treeGui.Visible)
        or (G.hangarOpen and G.hangarOpen()) or (G.ammoPanelOpen and G.ammoPanelOpen())   -- 挂载编辑器（Hangar.lua）、配弹面板（WtAmmo.lua）开着
        or overBlocker(pos))
    end
    G.stageFree = free   -- 整备、测试用：这个位置按下去算不算拖车
    UIS.InputBegan:Connect(function(io, gp)
      if gp or not Stage or not free(io.Position) then return end
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
        if not gp and free(io.Position) then Stage.zoom(io.Position.Z) end
      elseif last and dragIo and (io == dragIo
        or (io.UserInputType == Enum.UserInputType.MouseMovement and dragIo.UserInputType == Enum.UserInputType.MouseButton1)) then
        local p = io.Position
        Stage.drag(p.X - last.X, p.Y - last.Y)
        last = p
      end
    end)
    -- 厂房没搭起来（模块没到 / 报错）时的底：一块深色（平时不显示）
    local back = frame(hangar, UDim2.fromScale(1, 1), nil, TH.C.BG, 0.04)
    back.Name = "Backdrop"
    back.ZIndex = 0
    back.Visible = false
    H.backdrop = back
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
  -- 交给整备（Workshop，下一步：挂载 / 弹药 · 改装 · 乘员 · 涂装 · 资料）：同一块 1280 × 720 缩放的画布、同一间 3D 厂房 / 停机坪
  --   G.techRoot：Root（UIScale 缩放，H.vw × H.vh 是缩放后的画布、H.scale 是缩放倍数）；G.hangarStage：HangarStage（focus / highlight / toScreen，见那个文件）；
  --   G.hangarParts：机库界面里整备时要收起来的那几层（下面建好以后填：ui、mid、top、row、dock、match）；G.hangarSel()：选中的那一辆（科技树的项、键）
  G.techRoot = root
  G.hangarStage = Stage
  G.hangarParts = H
  local ui = frame(hangar, UDim2.fromScale(1, 1), nil, nil, 1)    -- 整套界面（「只看车」时整个藏起来）
  ui.Name = "UI"
  H.ui = ui
  do   -- 顶栏底下一条深色渐变（上浓下淡），字和按钮压在 3D 机库上也清楚
    local band = frame(ui, UDim2.new(1, 0, 0, 92), nil, RGB(0, 0, 0), 0)
    band.Name = "TopBand"
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
    g.Parent = band
  end
  local mid = frame(ui, UDim2.fromScale(1, 1), nil, nil, 1)       -- 中间那一层（国旗、乘员、这一局的信息）：开着研究窗口时让开
  mid.Name = "Mid"
  H.mid = mid

  -- 三种模式（服务器 Tech.lua：准备阶段按票数，开战定住，workspace 属性 WtMode；每人投的票是玩家属性 ModeVote）
  local MODE_NAME = { rb = L("历史", "Realistic") }   -- 只有历史（11-27 删了全真、街机）
  local selSlot = 1   -- 出击阵容里选中的第几位（厂房里停的、右下「战斗」出的都是这一辆）
  -- 选中的那一辆：键、科技树里的项
  local function selIt()
    local key = lineupOf(tree.nat)[selSlot]
    return key and TT.get(key), key, selSlot
  end
  G.hangarSel = selIt
  -- 「帮助」：怎么玩
  local function toggleHelp()
    if H.help then
      H.help.Visible = not H.help.Visible
      return
    end
    local p = frame(hangar, UDim2.new(0, 560, 0, 306), UDim2.new(0.5, -280, 0.5, -170), TH.C.PANEL, 0.04)
    p.Name = "Help"
    p.ZIndex = 20
    p.Active = true
    TH.stroke(p, true)
    corners(p, TH.C.TEXT, 12, 2, 5)
    local t = text(p, L("怎么玩", "HOW TO PLAY"), UDim2.new(1, -80, 0, 26), UDim2.new(0, 18, 0, 12), TH.S.title)
    t.Font = TH.F.bold
    local x = button(p, "×", UDim2.new(0, 32, 0, 28), UDim2.new(1, -44, 0, 10))
    x.MouseButton1Click:Connect(function() p.Visible = false end)
    local lines = {
      L("「研究」开科技树：打仗挣研究点，研究完用金币买下，再放进出击阵容（最多 5 辆）。", "RESEARCH opens the tech tree: earn research points in battle, buy researched vehicles with coins, then add them to your lineup (up to 5)."),
      L("底下点一张卡片选中，再点右下的「战斗」：直接坐在车里 / 飞机里出现在自己基地；车没了回到这里。", "Pick a slot, then press TO BATTLE: you spawn inside it at your base. Lose it and you come back here."),
      L("准备阶段第一辆免费；开战以后出车要出击点（SP），打得好挣得多。每辆车有一次备用。", "The first vehicle is free during preparation; after that deploying costs spawn points (SP) earned in battle. Each vehicle has one backup."),
      L("「技能树」给这一位的乘员加点；齿轮是这辆车的改装，炮弹是配弹，「i」是资料卡和装甲；右边「试驾」开出去试。", "CREW spends crew skill points; the gear opens modifications, the shells open the ammo loadout, \"i\" shows stats and armor; TEST DRIVE is on the right."),
      L("右下投票选这一局的地图（准备阶段按票数定）。换系：点左上的国旗打开科技树，在科技树里点国旗。「观战」看队友。", "Bottom right: vote for the next map (decided by votes during preparation). To switch nation, click the flag at the top left to open the tech tree and pick a flag there. SPECTATE watches teammates."),
      L("按住空白处拖动转着看车，滚轮拉近拉远；「只看车」把界面藏起来。进了车按 F1 看全部按键。", "Drag on empty space to orbit the vehicle, wheel to zoom; HIDE UI hides the interface. Press F1 in a vehicle for all keys."),
    }
    for i, s in ipairs(lines) do
      local l = text(p, s, UDim2.new(1, -36, 0, 36), UDim2.new(0, 18, 0, 48 + (i - 1) * 42), 13, TH.C.TEXT)
      l.TextWrapped, l.TextTruncate, l.TextYAlignment = true, Enum.TextTruncate.None, Enum.TextYAlignment.Top
    end
    H.help = p
  end

  do   -- 顶上一排
    local x0nav
    local TY, THh = mobile and 14 or 28, mobile and 30 or 34
    local LX, XW = mobile and 14 or 24, mobile and 80 or 120   -- 11-25 照战雷重排：正中留给「加入战斗」，等级、大键都往左挪
    local NW, NG = mobile and 76 or 100, mobile and 8 or 12
    local IW, IG = mobile and 30 or 34, mobile and 8 or 14
    H.TY, H.TH = TY, THh
    -- 顶上一整条装进自己的一层（用户 11-25 截图：右边那排图标压在「加入战斗」上、等级圈压着 Roblox 的菜单键）：
    --   「加入战斗」按屏幕居中，图标跟着中线排（原来按 1280 宽的屏幕算死了绝对位置，屏幕一宽就压上去）；
    --   左边那组从 Roblox 自己的按钮右边开始（GuiService.TopbarInset）；屏幕窄到排不下时整条等比缩小（layoutTop）
    local top = frame(ui, UDim2.fromScale(1, 1), nil, nil, 1)
    top.Name = "TopRow"
    H.top = top
    local topScale = Instance.new("UIScale")
    topScale.Parent = top
    local leftEls = {}   -- { 元素, 相对左边起点的 x }
    -- 经验条（右端斜的）+ 压在它左头上的等级圈
    local xpBg = frame(top, UDim2.new(0, XW, 0, 18), UDim2.new(0, LX + 20, 0, TY + (THh - 18) / 2), INK, 0.1)
    xpBg.Name = "Xp"
    slant(xpBg, XW, 18)
    local xpFill = frame(xpBg, UDim2.new(0, 0, 1, 0), nil, RGB(58, 150, 76), 0)   -- 绿（不用蓝：docs/style.md）；比 GOOD 暗一点，白字压在上面看得清
    xpFill.Name = "Fill"
    local xpT = text(xpBg, "", UDim2.new(1, -26, 1, 0), UDim2.new(0, 18, 0, 0), TH.S.tiny, TH.C.TEXT)
    xpT.Name = "XpT"
    xpT.Font = TH.F.mono
    local lv = round(frame(top, UDim2.new(0, THh, 0, THh), UDim2.new(0, LX, 0, TY), RGB(6, 7, 8), 0))
    lv.Name = "Level"
    table.insert(leftEls, { lv, 0 })
    table.insert(leftEls, { xpBg, 20 })
    edge(lv, TH.C.TEXT, 0, 2)
    local lvT = text(lv, "1", UDim2.fromScale(1, 1), nil, mobile and TH.S.body or TH.S.sub, TH.C.TEXT, Enum.TextXAlignment.Center)
    lvT.Font = TH.F.bold
    H.xpW, H.xpFill, H.xpT, H.lvT = XW, xpFill, xpT, lvT
    -- 四个大键
    local x = LX + 20 + XW + 14
    local navs = {
      { "NavMenu", L("主菜单", "MAIN MENU"), "MENU", function() if G.showMenu then G.showMenu() end end },
      { "NavCrew", L("技能树", "CREW SKILLS"), "CREW", function()
        local it, key = selIt()
        if it and G.openCrew then G.openCrew(tree.nat, selSlot, key) end
      end },
      { "NavSpec", L("观战", "SPECTATE"), "SPECTATE", function() if G.wtSpecStart then G.wtSpecStart() end end },
    }
    for _, n in ipairs(navs) do
      local b = navBtn(top, n[2], zh and n[3] or nil, UDim2.new(0, NW, 0, THh), UDim2.new(0, x, 0, TY))
      b.Name = n[1]
      table.insert(leftEls, { b, x - LX })
      b.MouseButton1Click:Connect(n[4])
      if n[1] == "NavTree" then H.navTree = b end
      x += NW + NG
    end
    x0nav = x - NG - LX   -- 左边那组（等级圈 + 经验条 + 导航键）一共多宽
    G.hangarHasSpec = true   -- WtCam.lua：机库顶上已经有「观战」，它自己那个按钮不画
    -- 四个方图标键（图标是拼的：齿轮、两发炮弹、圈里的 ? 和 i）；鼠标放上去底下出一行字
    local LIGHT = TH.C.TEXT
    local function gear(b)
      local c = frame(b, UDim2.new(0, 20, 0, 20), UDim2.new(0.5, -10, 0.5, -10), nil, 1)
      for i = 0, 3 do frame(c, UDim2.new(0, 4, 0, 20), UDim2.new(0.5, -2, 0, 0), LIGHT, 0).Rotation = i * 45 end
      round(frame(c, UDim2.new(0, 14, 0, 14), UDim2.new(0.5, -7, 0.5, -7), LIGHT, 0))
      round(frame(c, UDim2.new(0, 6, 0, 6), UDim2.new(0.5, -3, 0.5, -3), INK, 0))
    end
    local function wrench(b)   -- 扳手（改装）：齿轮让给「设置」
      local c = frame(b, UDim2.new(0, 20, 0, 20), UDim2.new(0.5, -10, 0.5, -10), nil, 1)
      local bar = frame(c, UDim2.new(0, 4, 0, 15), UDim2.new(0.5, -2, 0.5, -5), LIGHT, 0)
      bar.Rotation = 45
      local head = round(frame(c, UDim2.new(0, 11, 0, 11), UDim2.new(0, 9, 0, 0), LIGHT, 0))
      local jaw = frame(head, UDim2.new(0, 5, 0, 6), UDim2.new(0, 6, 0, 0), INK, 0)
      jaw.Rotation = 45
    end
    local function shells(b)
      local c = frame(b, UDim2.new(0, 20, 0, 20), UDim2.new(0.5, -10, 0.5, -10), nil, 1)
      for i = 0, 1 do
        local x0 = 3 + i * 9
        round(frame(c, UDim2.new(0, 5, 0, 8), UDim2.new(0, x0, 0, 1), LIGHT, 0))          -- 弹头
        frame(c, UDim2.new(0, 5, 0, 10), UDim2.new(0, x0, 0, 6), LIGHT, 0)                 -- 弹体
        frame(c, UDim2.new(0, 7, 0, 2), UDim2.new(0, x0 - 1, 0, 17), LIGHT, 0)             -- 底缘
      end
    end
    local function letter(ch)
      return function(b)
        local c = round(frame(b, UDim2.new(0, 20, 0, 20), UDim2.new(0.5, -10, 0.5, -10), nil, 1))
        edge(c, LIGHT, 0, 2)
        text(c, ch, UDim2.fromScale(1, 1), nil, TH.S.body, LIGHT, Enum.TextXAlignment.Center).Font = TH.F.bold
      end
    end
    local icons = {
      { "ModsBtn", L("改装", "Modifications"), wrench, function() local it = selIt() if it and G.openMods then G.openMods(it) end end },
      { "AmmoBtn", L("弹药", "Ammo loadout"), shells, function()   -- 配弹（C：WtAmmo.lua）：地面车的主炮每种弹带几发
        local it, key = selIt()
        if it and it.branch == "ground" and G.openAmmo then
          local md = tree.mods and tree.mods[key]
          local fx = WM.fx and WM.fx(it, md and md.done)
          G.openAmmo(key, fx and fx.ammo)
        elseif it and G.openWorkshop and G.openWorkshop(it, "arms") then
          -- 飞机 / 直升机（用户 11-27「整个给载具配置武器的系统 做的很粗糙 我需要非常艺术经验的效果 参考战雷」）：打开整备的挂载页（Workshop.lua / WsArms.lua）——
          --   舞台就是这间停机坪，改动即时存（Tech.lua treeLoad），出击、试驾都按它
        elseif it and G.openHangar then
          -- 整备没搭起来（模块出错）：退回老的 3D 挂载编辑器（Hangar.lua）——按存的那套打开，「保存」发服务器存档
          local a = AD.get(it.play)
          if not (a and a.st and #a.st > 0) then return end
          local load, pk, fuel = airLoad(it)
          G.openHangar(it.play, load, function(nl, npk, nf)
            tree.load = tree.load or {}
            tree.load[key] = { p = npk, l = nl, f = nf }   -- 先按自己存的摆（服务器收完再推一份 Tree 过来，内容一样）
            act("treeLoad", key, nl, npk or false, nf)   -- 没有预设传 false：中间夹着 nil 的参数表有空洞（同 Depot.lua）
            if hangar.Visible and G.refreshLineup then G.refreshLineup() end   -- refreshHangar 在下面才定义
          end, pk, { fuel = fuel })
        end
      end },
      { "HelpBtn", L("帮助", "Help"), letter("?"), toggleHelp },
      { "SettingsBtn", L("设置（兑换码在这里）", "Settings (codes here)"), gear, function() if G.openSettings then G.openSettings() end end },   -- 用户 11-25：设置界面重做、兑换码放在设置里（Settings.lua）
      { "InfoBtn", L("资料卡 · 装甲", "Stats · armor"), letter("i"), function() local it = selIt() if it and G.openInfo then G.openInfo(it) end end },
    }
    -- 正中「加入战斗」（同战雷：主按钮在顶栏正中；名字仍叫 HangarGo）+ 底下这一局：地图、阶段和时间、战斗等级
    local JW, JH = mobile and 150 or 210, mobile and 38 or 46
    do
      local bb = Instance.new("TextButton")
      bb.Name = "HangarGo"
      bb.AutoButtonColor = false
      bb.Text = ""
      -- 11-25「没有那种感觉」：实心琥珀的大主按钮（上亮下暗），一眼就是它
      bb.BackgroundColor3, bb.BackgroundTransparency, bb.BorderSizePixel = AMBER, 0, 0
      bb.Size, bb.Position = UDim2.new(0, JW, 0, JH), UDim2.new(0.5, -JW / 2, 0, TY - (JH - THh) / 2)
      bb.Parent = top
      TH.corner(bb, 3)
      TH.grad(bb, RGB(255, 214, 120), RGB(200, 132, 30))
      TH.stroke(bb, true, RGB(255, 236, 190)).Transparency = 0.5
      -- 上面一行大字、下面一行小字（车名 · 免费），两行不叠
      local bt = text(bb, L("加入战斗", "TO BATTLE"), UDim2.new(1, 0, 0, JH - 17), UDim2.new(0, 0, 0, 2), mobile and TH.S.sub or 22, RGB(24, 18, 8), Enum.TextXAlignment.Center)
      bt.Font = TH.F.title
      local bs = text(bb, "", UDim2.new(1, -12, 0, 13), UDim2.new(0, 6, 1, -15), TH.S.tiny, RGB(60, 42, 14), Enum.TextXAlignment.Center)
      bs.Name = "GoSub"
      bs.Font = TH.F.bold
      bb.MouseEnter:Connect(function() if H.goKey then TH.grad(bb, RGB(255, 228, 150), RGB(220, 150, 40)) end end)
      bb.MouseLeave:Connect(function() TH.grad(bb, RGB(255, 214, 120), RGB(200, 132, 30)) end)
      H.goBtn = bb
      -- 用户 11-26「点开战先匹配」：匹配中点一下排上（带着选中的这一辆）、再点取消；已经打起来了就直接加入（WtMatch.lua）
      bb.MouseButton1Click:Connect(function()
        local S = G.S or {}
        if S.phase == "queue" then
          if S.queued then act("matchCancel") elseif H.goKey then act("matchJoin", H.goKey) end
        elseif H.goKey then
          act("deployVeh", H.goKey)
        end
      end)
      H.goT, H.goSub = bt, bs
      H.go0 = { parent = top, size = bb.Size, pos = bb.Position, tSize = bt.Size, tPos = bt.Position, tTs = bt.TextSize, sPos = bs.Position, sTs = bs.TextSize }
      -- 局内选车时才出来：「退出战斗」（这一局不打了，回到匹配前的机库：WtMatch.lua matchLeave）
      local lw = mobile and 110 or 128
      local lb = button(top, L("退出战斗", "Leave battle"), UDim2.new(0, lw, 0, mobile and 24 or 28), UDim2.new(0.5, -lw / 2, 0, TY + THh + (mobile and 54 or 64)))
      lb.Name = "LeaveMatch"
      lb.TextSize = TH.S.small
      lb.Visible = false
      lb.MouseButton1Click:Connect(function() act("matchLeave") end)
      H.leaveBtn = lb
      -- 这一局（战雷那块「陆战 · 历史性能」）：地图（点了投下一局的图）、阶段和时间、战斗等级
      local MW = mobile and 260 or 330
      local card = frame(top, UDim2.new(0, MW, 0, mobile and 40 or 46), UDim2.new(0.5, -MW / 2, 0, TY + THh + (mobile and 8 or 10)), TH.C.PANEL, 0.18)
      card.Name = "Match"
      H.match = card   -- 整备时收起（正好压在整备的抬头上）
      TH.corner(card)
      TH.stroke(card)
      local mapB = Instance.new("TextButton")
      mapB.Name = "MapVote"
      mapB.AutoButtonColor, mapB.BackgroundTransparency, mapB.Text = false, 1, ""
      mapB.Size, mapB.Position = UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 0, 2)
      mapB.Parent = card
      local mapT = text(mapB, "", UDim2.new(1, -16, 1, 0), UDim2.new(0, 8, 0, 0), TH.S.body, TH.C.TEXT, Enum.TextXAlignment.Center)
      mapT.Name = "MapT"
      mapT.Font = TH.F.bold
      H.mapT, H.mapB = mapT, mapB
      -- 点地图：下面展开一列可选的图（投下一局的；现在打的那张标着「本局」）
      local list = frame(top, UDim2.new(0, MW, 0, 10), UDim2.new(0.5, -MW / 2, 0, TY + THh + (mobile and 52 or 60)), TH.C.PANEL, 0.04)
      list.Name = "MapList"
      list.Visible = false
      list.ZIndex = 30
      TH.corner(list)
      TH.stroke(list, true)
      local function fillList()
        clear(list)
        local Map = G.Map
        local ids = (Map and Map.ids) or { "sands" }
        local S = G.S or {}
        local cur = S.map or (Map and Map.id)
        for i, id in ipairs(ids) do
          local b = Instance.new("TextButton")
          b.Name = "Map_" .. id
          b.Size, b.Position = UDim2.new(1, -8, 0, 30), UDim2.new(0, 4, 0, 4 + (i - 1) * 32)
          b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = TH.C.TEXT, (id == cur) and 0.85 or 1, 0
          b.AutoButtonColor = true
          b.Text = ""
          b.ZIndex = 31
          b.Parent = list
          TH.corner(b)
          local nmT = (G.T and G.T("map." .. id .. ".name")) or id
          if nmT == "map." .. id .. ".name" then nmT = id end
          local t = text(b, nmT .. ((id == cur) and L("  ·  本局", "  ·  current") or ""), UDim2.new(1, -16, 1, 0), UDim2.new(0, 10, 0, 0), TH.S.body, TH.C.TEXT)
          t.ZIndex = 32
          b.MouseButton1Click:Connect(function()
            act("pickMap", id)
            list.Visible = false
          end)
        end
        list.Size = UDim2.new(0, MW, 0, 8 + #ids * 32)
      end
      mapB.MouseButton1Click:Connect(function()
        if G.S and G.S.pick then list.Visible = false return end   -- 局内（这一局算他的）：不能选图（用户 11-26「为什么局内还能选地图 去掉」）
        if not list.Visible then fillList() end
        list.Visible = not list.Visible
      end)
      H.mapList = list
      H.phaseT = text(card, "", UDim2.new(1, -16, 0, 16), UDim2.new(0, 8, 0, mobile and 22 or 26), TH.S.small, TH.C.MUTE, Enum.TextXAlignment.Center)
      H.phaseT.Name = "Phase"
      H.phaseT.Font = TH.F.mono
      H.brT = H.phaseT   -- 战斗等级和阶段写在同一行（refreshMode 里拼）
    end
    x = JW / 2 + (mobile and 14 or 22)   -- 相对屏幕中线
    for _, ic in ipairs(icons) do
      local b = Instance.new("TextButton")
      b.Name = ic[1]
      b.AutoButtonColor = false
      b.Text = ""
      b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = INK, 0.06, 0
      b.Size, b.Position = UDim2.new(0, IW, 0, IW), UDim2.new(0.5, x, 0, TY + (THh - IW) / 2)
      b.Parent = top
      corners(b, TH.C.TEXT, 7, 2, 3)
      ic[3](b)
      local tip = text(b, ic[2], UDim2.new(0, 140, 0, 16), UDim2.new(0.5, -70, 1, 9), TH.S.tiny, TH.C.TEXT, Enum.TextXAlignment.Center)
      tip.Name = "Tip"
      tip.TextStrokeTransparency = 0.4
      tip.Visible = false
      b.MouseEnter:Connect(function() b.BackgroundColor3 = HOVER tip.Visible = true end)
      b.MouseLeave:Connect(function() b.BackgroundColor3 = INK tip.Visible = false end)
      b.MouseButton1Click:Connect(ic[4])
      if ic[1] == "AmmoBtn" then H.ammoBtn, H.ammoTip = b, tip end
      H.icons = H.icons or {}
      table.insert(H.icons, { name = ic[1], b = b, pos = b.Position })   -- 整备开着时收起和页签重复的那几个、剩下的往左并（G.hangarWsMode）
      x += IW + IG
    end
    -- 右上：金币（硬币 + 斜头的条），左边一格 SP（这一局的出击点）
    local CWd = mobile and 112 or 134
    local coin = frame(top, UDim2.new(0, CWd, 0, 22), UDim2.new(1, -M0 - CWd, 0, TY + (THh - 22) / 2), INK, 0.1)
    coin.Name = "Coins"
    slant(coin, CWd, 22)
    local coinT = text(coin, "", UDim2.new(1, -34, 1, 0), UDim2.new(0, 22, 0, 0), TH.S.body, TH.C.TEXT)
    coinT.Font = TH.F.mono
    local disc = round(frame(top, UDim2.new(0, 26, 0, 26), UDim2.new(1, -M0 - CWd - 12, 0, TY + (THh - 26) / 2), RGB(226, 172, 48), 0))
    disc.Name = "Coin"
    edge(disc, RGB(140, 96, 18), 0, 1.5)
    edge(round(frame(disc, UDim2.new(0, 16, 0, 16), UDim2.new(0.5, -8, 0.5, -8), RGB(246, 204, 92), 0)), RGB(168, 118, 26), 0.2, 1)
    local spT = text(top, "", UDim2.new(0, 96, 0, 22), UDim2.new(1, -M0 - CWd - 12 - 104, 0, TY + (THh - 22) / 2), TH.S.small, TH.C.TEXT, Enum.TextXAlignment.Right)
    spT.Name = "SpChip"
    spT.Font = TH.F.mono
    spT.TextStrokeTransparency = 0.5
    H.coinT, H.spT = coinT, spT
    -- 顶栏排版：左边那组的宽、中间按钮的半宽、右边（图标 + SP + 金币）的宽，按屏幕宽度定起点和缩放
    local leftW = (x0nav or 0)
    local nIcons = #icons
    local function layoutTop()
      local W = 0
      pcall(function() W = ui.AbsoluteSize.X end)
      if not (W and W > 0) then
        local cam = workspace.CurrentCamera
        W = (cam and cam.ViewportSize.X > 0) and cam.ViewportSize.X or 1280
      end
      local inset = 0
      pcall(function()   -- Roblox 左上自己的按钮（菜单、聊天……）占到哪：顶栏这条和它同高，从它右边开始
        local r = game:GetService("GuiService").TopbarInset
        if r and r.Max.Y > TY then inset = r.Min.X end
      end)
      local half = JW / 2 + (mobile and 14 or 22)
      local rightW = nIcons * (IW + IG) + (mobile and 10 or 16) + CWd + 12 + 104 + M0
      local sc = 1
      for _ = 1, 4 do   -- 缩放影响左边起点（Roblox 按钮的宽是真像素）：迭代几次就定了
        local lx = math.max(LX, inset / sc + 8)
        local need = 2 * math.max(lx + leftW + 12 + JW / 2, half + rightW)
        sc = math.min(1, W / need)
      end
      local lx = math.max(LX, inset / sc + 8)
      topScale.Scale = sc
      top.Size = UDim2.fromScale(1 / sc, 1 / sc)
      for _, e in ipairs(leftEls) do
        e[1].Position = UDim2.new(0, lx + e[2], e[1].Position.Y.Scale, e[1].Position.Y.Offset)
      end
      H.topScale = sc
    end
    H.layoutTop = layoutTop
    pcall(function() ui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutTop) end)
    pcall(function() workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutTop) end)
    pcall(function() game:GetService("GuiService"):GetPropertyChangedSignal("TopbarInset"):Connect(layoutTop) end)
    task.defer(layoutTop)
    -- 「只看车」以后：右上角留一个键把界面叫回来
    local back = navBtn(hangar, L("显示界面", "SHOW INTERFACE"), nil, UDim2.new(0, 130, 0, THh), UDim2.new(1, -M0 - 130, 0, TY))
    back.Name = "ShowUI"
    back.Visible = false
    back.MouseButton1Click:Connect(function() ui.Visible = true back.Visible = false end)

    -- 左边一列国旗
    local FY = TY + THh + (mobile and 14 or 46)
    local flags = frame(mid, UDim2.new(0, FLAG_W, 0, 5 * (math.floor(FLAG_W * 0.62) + 28)), UDim2.new(0, M0, 0, FY), nil, 1)
    flags.Name = "Flags"
    H.flags = flags
    -- 右边：「乘员」框（点开这一位乘员的技能）+ 选中这一辆的名字、等级、乘员、改装 + 试驾 / 只看车
    local cw = mobile and 136 or 160
    local cb = Instance.new("TextButton")
    cb.Name = "CrewBtn"
    cb.AutoButtonColor = false
    cb.Text = ""
    cb.BackgroundColor3, cb.BackgroundTransparency, cb.BorderSizePixel = INK, 0.06, 0
    cb.Size, cb.Position = UDim2.new(0, cw, 0, 32), UDim2.new(1, -M0 - cw, 0, FY)
    cb.Parent = mid
    corners(cb, TH.C.TEXT, 8, 2, 4)
    local cbT = text(cb, "", UDim2.new(1, -40, 1, 0), UDim2.new(0, 12, 0, 0), TH.S.small, AMBER)
    cbT.Font = TH.F.title
    text(cb, "+", UDim2.new(0, 20, 1, 0), UDim2.new(1, -26, 0, 0), TH.S.sub, TH.C.TEXT, Enum.TextXAlignment.Center)
    cb.MouseEnter:Connect(function() cb.BackgroundColor3 = HOVER end)
    cb.MouseLeave:Connect(function() cb.BackgroundColor3 = INK end)
    cb.MouseButton1Click:Connect(navs[2][4])
    H.crewBoxT = cbT
    local sbox = frame(mid, UDim2.new(0, 420, 0, 150), UDim2.new(1, -M0 - 420, 0, FY + 40), nil, 1)
    sbox.Name = "Selected"
    local function right(y, ts, col, h)
      local t = text(sbox, "", UDim2.new(1, 0, 0, h or 16), UDim2.new(0, 0, 0, y), ts, col, Enum.TextXAlignment.Right)
      t.TextStrokeTransparency = 0.55
      return t
    end
    H.selName = right(0, mobile and TH.S.title or TH.S.big, TH.C.TEXT, 30)
    H.selName.Name = "SelName"
    H.selName.Font = TH.F.bold
    H.selSub = right(32, TH.S.small, TH.C.TEXT)
    H.selSub.Font = TH.F.mono
    H.selCrew = right(50, TH.S.small, TH.C.MUTE)
    H.selCrew.Name = "CrewT"
    H.selMods = right(67, TH.S.small, TH.C.MUTE)
    H.selMods.Name = "ModCount"
    H.selNote = right(84, TH.S.tiny, AMBER)
    local tb = button(sbox, L("试驾", "Test drive"), UDim2.new(0, 84, 0, 26), UDim2.new(1, -84, 0, 108))
    tb.Name = "HangarTest"
    tb.TextSize = TH.S.small
    tb.MouseButton1Click:Connect(function()
      local _, key = selIt()
      if key then act("testDrive", key) end
    end)
    H.testBtn = tb   -- 局内选车（S.pick）藏起来：下面按阶段刷新那段
    local vb = button(sbox, L("只看车", "Hide UI"), UDim2.new(0, 84, 0, 26), UDim2.new(1, -174, 0, 108))
    vb.Name = "ViewBtn"
    vb.TextSize = TH.S.small
    vb.MouseButton1Click:Connect(function() ui.Visible = false back.Visible = true end)
    H.viewBtn = vb
  end

  do   -- 底下（11-25 照战雷重排）：一条「科技树」把手 + 各国页签（点哪国换哪国），下面五个阵容槽位（refreshHangar 里填）
    local SW, SG, SH, BM = mobile and 148 or 172, mobile and 8 or 9, mobile and 92 or 104, mobile and 12 or 18
    H.SW, H.SG, H.SH = SW, SG, SH
    local row = frame(ui, UDim2.new(0, 5 * SW + 4 * SG, 0, SH), UDim2.new(0, M0, 1, -BM - SH), nil, 1)
    row.Name = "Lineup"
    H.row = row
    local DH = mobile and 26 or 30   -- 把手那一条的高
    local dock = frame(ui, UDim2.new(1, -2 * M0, 0, DH), UDim2.new(0, M0, 1, -BM - SH - DH - 6), TH.C.BG, 0.25)
    dock.Name = "Dock"
    TH.corner(dock)
    H.dock = dock
    H.dockTop = BM + SH + DH + 6   -- 科技树往上弹出来时下沿停在这条上面
    H.winBottom = H.dockTop + 6
    local handle = Instance.new("TextButton")
    handle.Name = "TreeHandle"
    handle.AutoButtonColor = false
    handle.Text = ""
    handle.BackgroundColor3, handle.BackgroundTransparency, handle.BorderSizePixel = TH.C.RAISE, 0.05, 0
    handle.Size, handle.Position = UDim2.new(0, mobile and 150 or 200, 1, 0), UDim2.new(0, 0, 0, 0)
    handle.Parent = dock
    TH.corner(handle)
    TH.stroke(handle, true)
    local ht = text(handle, "", UDim2.new(1, 0, 1, 0), nil, TH.S.sub, TH.C.TEXT, Enum.TextXAlignment.Center)
    ht.Font = TH.F.bold
    H.handleT = ht
    handle.MouseButton1Click:Connect(function()
      -- 按「科技树开着没有」（treeShown 记的 H.treeOpen），不按面板 Visible：往下滑着关的那 0.18 秒里面板还 Visible，
      --   原来这时点把手走 closeTree、被 closing 挡掉，什么都不发生；现在走 openTree（它会从现在的位置滑回来）
      if H.treeOpen then
        if H.closeTree then H.closeTree() end
      elseif G.openTechTree then
        G.openTechTree()
      end
    end)
    H.navTree = handle
    local nats = frame(dock, UDim2.new(1, -(mobile and 160 or 212) - 160, 1, 0), UDim2.new(0, mobile and 160 or 212, 0, 0), nil, 1)
    nats.Name = "Nations"
    local nl = Instance.new("UIListLayout")
    nl.FillDirection = Enum.FillDirection.Horizontal
    nl.SortOrder = Enum.SortOrder.LayoutOrder
    nl.Padding = UDim.new(0, mobile and 4 or 6)
    nl.Parent = nats
    H.nats = nats
    local airT = text(dock, "", UDim2.new(0, 150, 1, 0), UDim2.new(1, -158, 0, 0), TH.S.small, TH.C.MUTE, Enum.TextXAlignment.Right)
    airT.Name = "AirCount"
    H.airT = airT
  end
  -- 底下各国页签：小旗 + 国名，选中的白字、下面一道白线（点了换系：机库阵容、科技树都跟着换）
  local function dockNations(onPick)
    clear(H.nats)
    for i, nat in ipairs(TT.NATIONS) do
      local N = TT.NAT[nat]
      local on = nat == tree.nat
      local b = Instance.new("TextButton")
      b.Name = "Nat_" .. nat
      b.LayoutOrder = i
      b.Text = ""
      b.AutoButtonColor = false
      b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = TH.C.TEXT, on and 0.88 or 1, 0
      b.Size = UDim2.new(0, mobile and 78 or 100, 1, 0)
      b.Parent = H.nats
      local fl = frame(b, UDim2.new(0, mobile and 22 or 26, 0, mobile and 14 or 16), UDim2.new(0, 8, 0.5, mobile and -7 or -8), TH.C.BG, 0)
      fl.Name = "Flag"
      drawFlag(fl, nat)
      local t = text(b, zh and N.name or N.en, UDim2.new(1, -(mobile and 34 or 40), 1, 0), UDim2.new(0, mobile and 34 or 40, 0, 0), mobile and TH.S.small or TH.S.body, on and TH.C.TEXT or TH.C.MUTE)
      t.Font = on and TH.F.bold or TH.F.body
      if on then frame(b, UDim2.new(1, -8, 0, 2), UDim2.new(0, 4, 1, -2), TH.C.TEXT, 0) end
      b.MouseButton1Click:Connect(function() onPick(nat) end)
    end
  end
  local function refreshMode()
    -- 11-25「把那个选择真实度的图改成选地图吧」：顶上这一局那块写地图（点了投下一局的图）；模式照旧按服务器的（默认历史）
    local S = G.S or {}
    local mid = (S.map or (G.Map and G.Map.id)) or "sands"
    local mname = (G.T and G.T("map." .. mid .. ".name")) or mid
    if mname == ("map." .. mid .. ".name") then mname = mid end
    local cur = "rb"
    local inMatch = S.pick == true   -- 局内：只写这一局打的是什么图，不能点开选图（没有 ▼）
    H.mapT.Text = L("陆战 · ", "Ground · ") .. mname .. "  ·  " .. (MODE_NAME[cur] or MODE_NAME.rb) .. (inMatch and "" or "  ▼")
    if H.mapB then H.mapB.Active = not inMatch H.mapB.AutoButtonColor = false end
    if inMatch and H.mapList then H.mapList.Visible = false end
  end

  -- 厂房里停哪一辆：出击阵容里选中的（按真车涂装；有原模型的就是原模型）；飞机挂着存的那套挂载
  --   shownKey 是「键 | 挂载」：存了新挂载重新摆（同一辆只换模型、镜头不动：整备里正看着某个挂点时不跳回全景）
  local shownKey, shownVeh = nil, nil
  G.hangarShown = function() return shownKey end   -- 测试用
  -- 整备（Workshop.lua / WsArms.lua）给停机坪上这架飞机的：airOver 换上预览 / 刚改的挂载（只认同一架）、airPose 摆的姿势（弹舱开着）；
  --   airShown 现在摆着的 { M = AirModels 的模型表, d, cf 飞机的 CFrame, it, key, load }；每次（重新）搭好以后回调 G.onHangarAir(airShown)
  --   （整备把挂点上的零件分组、补高亮、做装上的动效）
  local airOver, airPose, airShown = nil, nil, nil
  -- 整备里来回换挂载（悬停预览、装上、撤销）：同一架搭过的几套先收着（最多 6 套，留最近用过的），换回来只换模型、不重搭——
  --   原模型几百个零件，扫一列武器卡时每次重搭会卡一下；点了装上的那一套就是刚才悬停预览搭好的那套，直接换上。整备关了、换了别的车全部清掉
  local airCache = {}   -- [「键 | 挂载」] = { A = 当时的 airShown, t = 收进来的时间 }
  local function airCacheClear()
    for k, e in pairs(airCache) do
      pcall(function() e.A.M.model:Destroy() end)
      airCache[k] = nil
    end
  end
  G.hangarAirCacheClear = airCacheClear
  G.hangarAirCached = function() local n = 0 for _ in pairs(airCache) do n += 1 end return n end   -- 测试用
  local function showVehicle(it)
    if not (Stage and Stage.active()) then return end
    local key = it and it.key or ""
    local aload = it and it.branch ~= "ground" and ((airOver and airOver.key == key and airOver.load) or (airLoad(it))) or nil
    local sig = key .. "|" .. loadSig(aload)
    if shownKey == sig then return end
    local prevSig, prevAir = shownKey, airShown
    shownKey = sig
    local keepCam = shownVeh == key and key ~= ""
    if shownVeh ~= key then airCacheClear() end
    shownVeh = key
    airShown = nil
    -- 整备开着、还是这一架：现在摆着的那套收进缓存（不销毁）
    if H.wsOn and prevAir and prevAir.key == key and prevSig and Stage.take then
      local m = Stage.take()
      if m then
        airCache[prevSig] = { A = prevAir, t = os.clock() }
        local n, oldK, oldT = 0, nil, math.huge
        for k, e in pairs(airCache) do
          n += 1
          if e.t < oldT then oldK, oldT = k, e.t end
        end
        if n > 6 and oldK then
          pcall(function() airCache[oldK].A.M.model:Destroy() end)
          airCache[oldK] = nil
        end
      end
    end
    if not it then
      Stage.put(nil)
      return
    end
    -- 飞机、直升机停在露天机场停机坪上（用户 11-25「查看飞机和直升机的时候单独做个背景吧」），车停在厂房里
    if Stage.mode then Stage.mode((it.branch ~= "ground") and "air" or "ground") end
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
        local ce = H.wsOn and airCache[sig] or nil
        local ok, M = false, nil
        if ce and ce.A and ce.A.M and ce.A.M.model then   -- 搭过这一套：直接换上
          airCache[sig] = nil
          ok, M = true, ce.A.M
        else
          -- 真机上用 MicroProfiler 看一套原模型飞机搭多久（整备悬停预览的卡顿就看这一段）
          local prof = debug and debug.profilebegin
          if prof then pcall(debug.profilebegin, "hangarAirBuild") end
          ok, M = pcall(AM.build, a, side, aload or AD.presetLoad(a))
          if prof then pcall(debug.profileend) end
        end
        if ok and M and M.model then
          local cf = base * CFrame.new(0, a.gearH or 6, 0)
          pcall(AM.pose, M, cf, airPose or { gear = 1, thr = 0 }, os.clock())
          Stage.put(M.model, { L = a.L or 50, W = a.W or 36, H = (a.H or 13) + (a.gearH or 0) * 0.5 }, keepCam)
          airShown = { M = M, d = a, cf = cf, it = it, key = key, load = aload or AD.presetLoad(a), AM = AM }
          if G.onHangarAir then
            local okH, err = pcall(G.onHangarAir, airShown)
            if not okH and G.showError then G.showError("local workshop: " .. tostring(err)) end
          end
          return
        end
      end
    end
    Stage.put(nil)
  end
  G.hangarAir = function() return airShown end
  -- 换上一套挂载（整备：悬停预览、刚改的）；nil 还原成存的那套。返回 true = 重新搭了模型（同一架只换模型、镜头不动）
  G.hangarAirLoad = function(load)
    local it = selIt()
    airOver = (load and it) and { key = it.key, load = table.clone(load) } or nil
    local before = shownKey
    if hangar.Visible then showVehicle(it) end
    return shownKey ~= before
  end
  -- 摆姿势（整备：放下起落架、打开弹舱 { gear = 1, bay = 1, bayS = 1, thr = 0 }）；nil 回到机库平时的样子
  G.hangarAirPose = function(c)
    airPose = c
    local a = airShown
    if a and a.M and a.AM then pcall(a.AM.pose, a.M, a.cf, c or { gear = 1, thr = 0 }, os.clock()) end
  end

  -- 正在试驾（服务器 Tech.lua testDrive 给车 / 飞机的模型打 TestDrive 属性）：Drive.lua、Interior.lua 也看这个
  G.inTestDrive = function()
    local d = G.drive
    local em = d and d.em
    if em and em:GetAttribute("TestDrive") == true then return true end
    local f = G.fly
    local fm = f and f.em
    return fm ~= nil and fm:GetAttribute("TestDrive") == true
  end

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
    local air = it.branch == "air" or it.branch == "heli"
    -- 飞机（同服务器 WtMatch：用户 11-25「第一辆必须是地面车，飞机要攒点数才能出」）：先出一辆地面车；一直要 SP，不免费
    --   用户 11-26「不要写先出击地面车 你直接禁止选飞机就行」：不写字，第三个返回值说这张卡禁选（卡片压暗、点了不理）——只在局内选车（S.pick）禁选。
    --   用户 11-27「飞机试驾不了」：原来不管在不在局里都禁选——S.wt 一直有（WtMatch.wtPersonal 不在局里也发这一局的账，没出过车 ground 就是 false），
    --   匹配中的机库里阵容的飞机、直升机点不动，右边「试驾」只能开地面车（乘员、改装、挂载也点不到）。
    --   不在局里照样能选（试驾、看车、改装）；匹配中（还没进局，谁都出不了车）只淡淡写这一型要多少 SP，不压暗、不拦「开战」
    if air and not w.ground then
      if S.pick then return nil, BAD, true end
      if S.phase == "queue" then
        local ok, v = pcall(Config.WtCost, it.play, cat, 0)
        return ok and v and ("SP " .. v) or nil, FAINT
      end
    end
    local c = 0
    if air or (S.phase == "battle" and not w.free) then
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
  cTitle.Font = Enum.Font.BuilderSansMedium
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

  -- 卡片上的车：HudIcons 里这一型的侧面剪影；没有就用通用的（飞机、直升机的符号），地面车没有就空着（写了车种、名字）
  local function picOn(img, it)
    -- 先用写实车图（用户 11-25「主页和科技树的载具图用实拍图吧 然后角度要像战雷那样」：HudArt 的 G.vehPicOn），没有才用白色剪影
    if G.vehPicOn and G.vehPicOn(img, it.branch ~= "ground", it.play, it.model, it.base) then
      img:SetAttribute("Photo", true)
      return
    end
    img:SetAttribute("Photo", nil)
    if not G.hudIconOn then return end
    local pre = (it.branch == "ground") and "veh_" or "air_"   -- 战机、直升机的剪影都在 air_ 下
    -- 同族变体（T-72A 借 T-72B3 的模型）没有自己的图标：用模型那一型的；再退到 VehDefs 的 like（科技树 M1A1 开 m1a1base、不写 model：同驾驶界面 VehHud）
    --   （按下标走：model / base 常常是 nil，ipairs 碰到 nil 就停了）
    local dl = it.branch == "ground" and VD.get(it.play or "")
    local keys = { it.play, it.model, it.base, dl and dl.like or nil }
    for i = 1, 4 do
      local k = keys[i]
      if k and G.hudIconOn(img, pre .. tostring(k)) then return end
    end
    if it.branch ~= "ground" then
      local d = AD.get(it.play)
      G.hudIconOn(img, (d and d.kind == "heli") and "heliMark" or "planeMark")
    end
  end
  -- 顶上的等级圈、经验条、SP、金币（服务器每次推状态都刷）
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
    local c = me:GetAttribute("Coins")
    H.coinT.Text = (me:GetAttribute("CoinsInf") == true) and "∞" or ((type(c) == "number") and fmtNum(c) or "—")
    local w2 = G.S and G.S.wt
    H.spT.Text = "SP " .. tostring(w2 and w2.sp or 0)
  end

  local function refreshHangar()
    H.bays = {}   -- 这一次重画的阵容卡片的等级底色（treeShown 开关它们）
    -- 底下一条（同战雷）：「科技树」把手 + 各国页签；点国家换系（机库阵容、科技树一起换）
    clear(H.flags)
    H.handleT.Text = ((H.treeOpen == true) and "︾  " or "︽  ") .. L("科技树", "Tech tree") .. ((H.treeOpen == true) and "  ︾" or "  ︽")   -- 按开没开（滑出那 0.18 秒面板还 Visible）
    dockNations(function(nat)
      if nat == tree.nat then return end
      if G.S and G.S.pick then return end   -- 局内选车：阵容跟着这一局，不换系
      tree.nat = nat
      selSlot = 1
      act("treeNat", nat)
      if H.treeOpen and G.treeView then G.treeView(nat) end   -- 正在滑出去：不再整棵重建（滑的时候卡一下）
      refreshHangar()
    end)
    clear(H.row)
    local keys = lineupOf(tree.nat)
    if not keys[selSlot] then selSlot = 1 end
    local function locked(k)   -- 这一局还没出过地面车：飞机、直升机禁选（服务器 WtMatch 照样拦）
      local x = k and TT.get(k)
      return x ~= nil and select(3, spState(x)) == true
    end
    if locked(keys[selSlot]) then
      for i = 1, #keys do if not locked(keys[i]) then selSlot = i break end end
    end
    do   -- 底下那一条右头：阵容里几个飞行单位（用户 11-25「最多两个飞行单位」）
      local na = 0
      for _, k in ipairs(keys) do local x = TT.get(k) if x and (x.branch == "air" or x.branch == "heli") then na += 1 end end
      H.airT.Text = L("飞行单位 ", "Aircraft ") .. na .. " / 2"
      H.airT.TextColor3 = (na >= 2) and AMBER or TH.C.MUTE
    end
    local rb, cap = brCap()
    local SW, SG = H.SW, H.SG
    for i = 1, 5 do
      local key = keys[i]
      local it = key and TT.get(key)
      local on = it ~= nil and i == selSlot
      local card = Instance.new("TextButton")
      card.Name = it and ("Line_" .. key) or ("Empty_" .. i)
      card.AutoButtonColor = false
      card.Text = ""
      card.Size, card.Position = UDim2.new(0, SW, 1, 0), UDim2.new(0, (i - 1) * (SW + SG), 0, 0)
      -- 同科技树卡片（11-25「没有设计感」）：深色底、选中的琥珀描边 + 左边琥珀色条，车图在渐变底板上
      card.BackgroundColor3, card.BackgroundTransparency, card.BorderSizePixel = RGB(27, 31, 36), on and 0.02 or 0.12, 0
      card.Parent = H.row
      TH.corner(card, 3)
      if on and it then TH.glow(card) else TH.stroke(card, false, TH.C.LINE).Transparency = 0.84 end
      if it then
        local over = cap ~= nil and it.br > cap + 0.05   -- 超出这一局能出的战斗等级（点了服务器也会说）
        local lock = locked(key)   -- 禁选（还没出过地面车的飞机）：整张卡压暗，点了不理
        local strip = frame(card, UDim2.new(0, 3, 1, -8), UDim2.new(0, 3, 0, 4), on and AMBER or RGB(80, 86, 92), 0)
        TH.corner(strip, 1)
        -- 等级底色铺满整张卡（用户 11-26「坦克背景颜色没有填满」）：上面等级色、往下淡进深色（名字压在暗的那头）
        local bay = frame(card, UDim2.fromScale(1, 1), nil, RGB(255, 255, 255), 0.3)
        bay.Name = "Bay"
        bay.ZIndex = 0
        TH.corner(bay, 3)
        TH.rankGrad(bay, it.rank)   -- 等级底色（用户 11-25：不同等级的载具背景颜色要有区别）
        -- 用户 11-25 晚「主界面不打开科技树 就别显示载具背景颜色了」：只有科技树开着时阵容卡片才画等级底色（treeShown 跟着开关）
        bay.Visible = H.treeOpen == true or (G.S ~= nil and G.S.pick == true)   -- 局内选车：一直画等级底色（用户 11-26「载具背后的背景颜色加上」）
        H.bays = H.bays or {}
        table.insert(H.bays, bay)
        -- 车图：写实车图（原模型按战雷那个角度拍的，HudArt G.vehPicOn）；没有才退回白色剪影
        local img = Instance.new("ImageLabel")
        img.Name = "Pic"
        img.BackgroundTransparency = 1
        img.ScaleType = Enum.ScaleType.Fit
        img.Size, img.Position = UDim2.new(1, -20, 1, -46), UDim2.new(0, 10, 0, 18)
        img.ImageColor3 = on and TH.C.TEXT or TH.C.MUTE
        img.ImageTransparency = over and 0.55 or 0.1
        img.Parent = card
        picOn(img, it)
        if img:GetAttribute("Photo") then
          img.ImageTransparency = over and 0.5 or 0
          if not on then img.ImageColor3 = RGB(200, 200, 200) end   -- 没选中的稍暗一点
        end
        if lock then
          img.ImageTransparency = 0.72
          img.ImageColor3 = RGB(120, 124, 128)
          bay.BackgroundTransparency = 0.82
          card.BackgroundTransparency = 0.35
          card.AutoButtonColor = false
          card:SetAttribute("Locked", true)
        end
        local no = text(card, tostring(i), UDim2.new(0, 14, 0, 14), UDim2.new(0, 7, 0, 4), TH.S.tiny, FAINT)
        no.Font = TH.F.mono
        if it.stand then   -- 还没有自己的模型：借的是哪一型写在右边和科技树详情里
          text(card, L("暂用模型", "stand-in"), UDim2.new(0, 70, 0, 14), UDim2.new(0, 22, 0, 4), 10, GOLD)
        elseif it.model then   -- 性能是自己的，模型借同族的
          text(card, L("同族模型", "family model"), UDim2.new(0, 70, 0, 14), UDim2.new(0, 22, 0, 4), 10, TH.C.MUTE)
        end
        local br = text(card, TT.brText(it.br), UDim2.new(0, 44, 0, 14), UDim2.new(1, -50, 0, 4), TH.S.small, over and BAD or (on and TH.C.TEXT or TH.C.MUTE), Enum.TextXAlignment.Right)
        br.Name = "Br"
        br.Font = TH.F.mono
        local n1 = text(card, nm(it), UDim2.new(1, -12, 0, 18), UDim2.new(0, 6, 1, -36), mobile and TH.S.body or TH.S.sub, (over or lock) and FAINT or TH.C.TEXT, Enum.TextXAlignment.Center)
        n1.Name = "VehName"
        n1.Font = TH.F.bold
        n1.TextStrokeTransparency = 0.5
        local spTx, spC = spState(it)
        if over then spTx, spC = L("超出本局战斗等级", "Above battle BR"), BAD end
        local st = text(card, spTx or "", UDim2.new(1, -12, 0, 14), UDim2.new(0, 6, 1, -19), TH.S.tiny, spC or DIM, Enum.TextXAlignment.Center)
        st.Name = "Sp"
        local slotI = i
        card.MouseButton1Click:Connect(function()
          if lock then return end
          if selSlot ~= slotI then
            selSlot = slotI
            refreshHangar()
          end
        end)
      else
        text(card, "+", UDim2.new(1, 0, 0, 24), UDim2.new(0, 0, 0.5, -26), TH.S.title, FAINT, Enum.TextXAlignment.Center)
        text(card, L("研究载具", "Research vehicles"), UDim2.new(1, -8, 0, 16), UDim2.new(0, 4, 0.5, 2), TH.S.tiny, FAINT, Enum.TextXAlignment.Center)
        card.MouseButton1Click:Connect(function() if openTree then openTree() end end)
      end
    end
    -- 右边：选中这一辆
    local key = keys[selSlot]
    local it = key and TT.get(key)
    if it then
      local N = TT.NAT[it.nat]
      H.selName.Text = nm(it)
      H.selSub.Text = (zh and N.name or N.en) .. " · " .. L("等级 ", "Rank ") .. TT.RANKS[it.rank].roman .. " · BR " .. TT.brText(it.br) .. " · " .. tostring(it.year)
      local cs = tree.crew and tree.crew[tree.nat] and tree.crew[tree.nat][tostring(selSlot)] or { xp = 0 }
      local cfree = WC.free(cs)
      H.selCrew.Text = L("乘员 ", "Crew level ") .. WC.level(cs.xp) .. L(" 级", "") .. ((cfree > 0) and (" · " .. L("技能点 ", "points ") .. cfree) or "")
      H.selCrew.TextColor3 = (cfree > 0) and GOLD or TH.C.MUTE
      local md = tree.mods and tree.mods[key]
      local nDone, nAll = WM.count(it, md and md.done)
      H.selMods.Text = L("改装 ", "Mods ") .. nDone .. " / " .. nAll .. "  ·  " .. L("自由研究点 ", "free RP ") .. fmtNum(tree.free[tree.nat] or 0)
      H.selMods.TextColor3 = (nDone == nAll) and GOOD or TH.C.MUTE
      if it.stand then
        H.selNote.Text = L("还没有自己的模型：暂用 ", "Stand-in model: ") .. vname(it.base or it.play)
      elseif it.model then
        H.selNote.Text = L("模型暂用同族的 ", "Family model: ") .. vname(it.model)
      else
        H.selNote.Text = ""
      end
      H.crewBoxT.Text = L("乘员 · ", "CREW · ") .. ((it.branch == "air") and L("战机", "AIRCRAFT") or (it.branch == "heli") and L("直升机", "HELICOPTERS") or L("坦克", "TANKS"))
    else
      H.selName.Text = L("出击阵容是空的", "Lineup is empty")
      H.selSub.Text = L("点「研究」，买下的车放进阵容", "Open RESEARCH and add owned vehicles")
      H.selCrew.Text, H.selMods.Text, H.selNote.Text = "", "", ""
      H.crewBoxT.Text = L("乘员", "CREW")
    end
    -- 弹药键：地面车配弹、飞机 / 直升机打开整备的挂载页（Workshop.lua）；没有挂点的直升机（运输型）、没车时才淡掉
    if H.ammoBtn then
      local ad = it and it.branch ~= "ground" and AD.get(it.play)
      local can = it ~= nil and ((it.branch == "ground" and G.openAmmo ~= nil) or (ad and ad.st and #ad.st > 0 and (G.openWorkshop ~= nil or G.openHangar ~= nil)))
      H.ammoBtn.BackgroundTransparency = can and 0.06 or 0.5
      H.ammoBtn:SetAttribute("Off", not can)
      if H.ammoTip then H.ammoTip.Text = (it and it.branch ~= "ground") and L("挂载", "Loadout") or L("弹药", "Ammo loadout") end
    end
    -- 右下「战斗」：出选中的那一辆；出不了（超出战斗等级、备用用完、SP 不够）就灰掉、写原因
    local can, why = it ~= nil, nil
    if it then
      local spTx, spC = spState(it)
      why = spTx
      if cap ~= nil and it.br > cap + 0.05 then can, why = false, L("超出本局战斗等级", "Above battle BR") end
      if spC == BAD then can = false end
    end
    H.goKey = can and key or nil
    H.goT.TextColor3 = can and RGB(24, 18, 8) or RGB(80, 70, 50)
    if H.goBtn then H.goBtn.BackgroundTransparency = can and 0 or 0.45 end
    H.goSub.Text = it and (nm(it) .. (why and ("  ·  " .. why) or "")) or L("先去研究一辆车", "Research a vehicle first")
    H.goSub.TextColor3 = (it and not can) and RGB(150, 30, 20) or RGB(60, 42, 14)
    -- 顶上这一局那块的第二行：阶段和时间（每次推状态写）后面接战斗等级
    H.brStr = rb and (L("本局 BR ", "BR ") .. TT.brText(rb) .. L("（可出到 ", " (up to ") .. TT.brText(cap) .. L("）", ")"))
      or (L("阵容 BR ", "Lineup BR ") .. TT.brText(TT.lineupBr(keys)))
    refreshTop()
    showVehicle(it)
  end
  G.refreshLineup = refreshHangar   -- 不叫 G.refreshHangar：Hangar.lua（改挂载）的刷新函数叫这个名字，顶掉了它就坏了
  G.hangarSelect = function(i) selSlot = i refreshHangar() end   -- 测试用
  -- 局内出击页（WtSpawn.lua，战雷的重生界面；用户 11-28「被击毁重新召唤载具要有这个界面」）借这边的阵容和规矩：
  --   每一位的车、名字、战斗等级、这一局要多少 SP（spState）、禁选（还没出过地面车的飞机）、超出本局战斗等级、能不能出；选中第几位
  G.techLineup = function()
    local keys = lineupOf(tree.nat)
    local _, cap = brCap()
    local out = {}
    for i = 1, 5 do
      local key = keys[i]
      local it = key and TT.get(key)
      if it then
        local spTx, spC, lock = spState(it)
        local over = cap ~= nil and it.br > cap + 0.05
        out[i] = { key = key, it = it, name = nm(it), br = TT.brText(it.br), sp = over and L("超出本局战斗等级", "Above battle BR") or spTx,
          spC = over and BAD or spC, lock = lock == true, over = over, can = (not over) and spC ~= BAD and lock ~= true }
      end
    end
    return out, selSlot
  end
  G.techSelectSlot = function(i) if selSlot ~= i then selSlot = i refreshHangar() end end
  G.techPicOn = function(img, it) picOn(img, it) end
  me:GetAttributeChangedSignal("Coins"):Connect(function() if hangar.Visible then refreshTop() end end)
  me:GetAttributeChangedSignal("CoinsInf"):Connect(function() if hangar.Visible then refreshTop() end end)

  -- 顶栏的主按钮放哪：br = true 放到右下角（局内选车），false 放回顶栏正中
  function H.placeGo(br)
    if H.goBR == br or not (H.goBtn and H.go0) then return end
    H.goBR = br
    local b, o = H.goBtn, H.go0
    if br then
      local vs = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
      local rowW = 5 * H.SW + 4 * H.SG
      local free = vs.X - 2 * M0 - rowW - 12
      local w = math.clamp(free, 200, mobile and 220 or 320)
      b.Parent = ui
      b.Size = UDim2.new(0, w, 0, H.SH)
      if free >= 200 then   -- 阵容卡右边放得下：和卡并排
        b.Position = UDim2.new(1, -(M0 + w), 1, -((mobile and 12 or 18) + H.SH))
      else                  -- 屏幕窄（手机）：放在「科技树」那一条上面、靠右
        b.Position = UDim2.new(1, -(M0 + w), 1, -(H.dockTop + 8 + H.SH))
      end
      H.goT.Size, H.goT.Position, H.goT.TextSize = UDim2.new(1, 0, 0, math.floor(H.SH * 0.5)), UDim2.new(0, 0, 0, math.floor(H.SH * 0.16)), mobile and 26 or 34
      H.goSub.Position, H.goSub.TextSize = UDim2.new(0, 6, 1, -(mobile and 22 or 28)), TH.S.small
    else
      b.Parent = o.parent
      b.Size, b.Position = o.size, o.pos
      H.goT.Size, H.goT.Position, H.goT.TextSize = o.tSize, o.tPos, o.tTs
      H.goSub.Position, H.goSub.TextSize = o.sPos, o.sTs
    end
  end
  -- 整备开着（Workshop.lua）：机库中间那一层（国旗、乘员框、选中车的资料）、顶栏下面「这一局」那块、「退出战斗」收起；
  --   阵容卡、科技树把手往下滑出 24 像素再藏（0.18 秒）；关了照原样滑回来（0.28 秒）。开着的时候 hangarSet、treeShown 也不把它们翻出来（H.wsOn）
  G.hangarWsMode = function(on, instant)
    on = on == true
    if (H.wsOn == true) == on then return end
    H.wsOn = on or nil
    H.wsBase = H.wsBase or { row = H.row.Position, dock = H.dock.Position }
    local S = G.S or {}
    local tok = {}
    H.wsTok = tok
    -- 顶栏上和整备页签重复的扳手（改装）、弹药（挂载）、i（资料）收起，剩下的（帮助、设置）往左并，不留空位；关了照原样摆回去
    local DUP = { ModsBtn = true, AmmoBtn = true, InfoBtn = true }
    local k = 0
    for _, e in ipairs(H.icons or {}) do
      if on and DUP[e.name] then
        e.b.Visible = false
      else
        k += 1
        e.b.Visible = true
        e.b.Position = on and (H.icons[k] and H.icons[k].pos or e.pos) or e.pos
      end
    end
    if on then
      if G.treeGui and G.treeGui.Visible and H.closeTree then H.closeTree() end   -- 科技树盖在机库上面：先收起
      H.mid.Visible = false
      if H.match then H.match.Visible = false end
      if H.mapList then H.mapList.Visible = false end
      if H.leaveBtn then H.leaveBtn.Visible = false end
      for _, k in ipairs({ "row", "dock" }) do
        local f = H[k]
        if instant then
          f.Visible = false
        else
          TH.tween(f, { Position = H.wsBase[k] + UDim2.new(0, 0, 0, 24) }, "out", "out")
          task.delay(TH.T.out, function() if H.wsTok == tok and H.wsOn then f.Visible = false end end)
        end
      end
    else
      airCacheClear()
      H.mid.Visible = not H.treeOpen
      if H.match then H.match.Visible = true end
      if H.leaveBtn then H.leaveBtn.Visible = S.pick == true end
      for _, k in ipairs({ "row", "dock" }) do
        local f = H[k]
        f.Visible = (k ~= "dock") or not S.pick
        if instant then
          f.Position = H.wsBase[k]
        else
          f.Position = H.wsBase[k] + UDim2.new(0, 0, 0, 24)
          TH.tween(f, { Position = H.wsBase[k] }, "panel", "out")
        end
      end
    end
    H.placeGo(S.pick == true and not H.wsOn)
  end

  -- 原来的部署界面（UI.lua）每次刷新都问一下：该显示部署页的时候机库盖上去
  local lastSig = nil
  function G.hangarSet(show)
    local want = show and G.hangarActive() and not (G.wtSpectating and G.wtSpectating())   -- C ⑮：观战的时候机库收起（WtCam.lua）
      and not (G.wtSpawnOn and G.wtSpawnOn())   -- 局内出击页（WtSpawn.lua，战雷的重生界面）开着：机库不出来
    if hangar.Visible ~= want then
      -- 出击（机库收起、人已经出生了）：镜头从机库一下切到战场——盖 0.1 秒黑再 0.25 秒淡开（UI.lua G.sceneFade；
      --   11-27「动画做出丝滑感」，顺便把进战场那一下的加载、阴影重画藏在黑里）。阵亡回机库 DeathFx 自己有淡黑淡开
      --   黑着等到镜头真到了车 / 飞机 / 船上（G.drive 可能比 S.alive 晚到），最多多等 0.8 秒（UI.lua 的 opt.ready）
      if hangar.Visible and not want and G.sceneFade and G.S and G.S.alive then
        G.sceneFade(0.1, 0.25, { ready = function() return G.drive ~= nil or G.fly ~= nil or G.sail ~= nil end })
      end
      hangar.Visible = want
      if Stage then
        shownKey, shownVeh = nil, nil
        if want then
          Stage.show(true)
        else
          -- 镜头已经有人接手了：开着主菜单（它自己的场景、视场角）一点不动；坐进了车 / 飞机、在观战只把视场角还回去
          local keep = nil
          if G.menuShown ~= nil and G.menuShown() == true then
            keep = "all"
          elseif G.drive ~= nil or G.fly ~= nil or (G.wtSpectating and G.wtSpectating()) then
            keep = "type"
          end
          Stage.show(false, keep)
          Stage.put(nil)
        end
      end
      H.backdrop.Visible = not (Stage and Stage.active())   -- 厂房没搭起来：垫一块深色的底
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
        local Q = S.queue
        if S.phase == "queue" then   -- 匹配中（用户 11-26）：还剩几秒、排了几个人（人不够补人机）
          H.phaseT.Text = ((Q and Q.left) and (L("匹配中 ", "Matchmaking ") .. fmt(Q.left) .. "  ·  " .. tostring(Q.n or 0) .. " / " .. tostring(Q.need or 16) .. L(" 人", ""))
            or L("点「开战」开始匹配", "Press TO BATTLE to queue")) .. (H.brStr and ("  ·  " .. H.brStr) or "")
        else
          H.phaseT.Text = ((S.phase == "prep") and (L("准备阶段 ", "Preparing ") .. fmt(S.left)) or (L("剩余时间 ", "Time left ") .. fmt(S.left)))
            .. (H.brStr and ("  ·  " .. H.brStr) or "")
        end
        -- 这一局的账（SP、免费那一辆、出过几次）、战斗等级变了：卡片上的「免费 / SP / 备用 / 用完」跟着刷新
        local w = S.wt or {}
        local sig = table.concat({ tostring(S.phase), tostring(w.sp), tostring(w.free), tostring(w.paid), tostring(#(w.order or {})), tostring(workspace:GetAttribute("WtBr")), tostring(S.pick) }, "|")
        if sig ~= lastSig then
          lastSig = sig
          refreshHangar()
        end
        -- 主按钮：匹配中是「开战」（排着的时候「取消匹配」+ 倒计时），打起来以后「加入战斗」
        if S.phase == "queue" then
          H.goT.Text = S.queued and L("取消匹配", "CANCEL") or L("开战", "TO BATTLE")
          if S.queued then
            H.goSub.Text = L("匹配中 ", "Matching ") .. fmt((Q and Q.left) or 0) .. L("  ·  人不够补人机", "  ·  bots fill in")
            H.goSub.TextColor3 = RGB(60, 42, 14)
            if H.goBtn then H.goBtn.BackgroundTransparency = 0 end
          end
        else
          -- 局内选车（用户 11-26「匹配完之后 两边再开始在局内有一个界面选择载具」，同战雷）：这一局算他的、现在没车（服务器 S.pick）——
          --   机库就是选车页（同一套外观：用户「你这个做的风格跟我目前的主界面风格完全不一样」），主按钮是「出击」，顶上多一个「退出战斗」
          H.goT.Text = S.pick and L("出击", "SPAWN") or L("加入战斗", "TO BATTLE")
        end
        if H.leaveBtn then H.leaveBtn.Visible = S.pick == true and not H.wsOn end
        -- 局内选车：「出击」放到右下角（用户 11-26「出击的按钮放到右下角吧」，同战雷的出击页），和阵容卡一样高；不在局里放回顶栏正中
        --   整备开着时（H.wsOn）照旧放在顶栏正中：右下是整备的底部条
        H.placeGo(S.pick == true and not H.wsOn)
        if H.nats then H.nats.Visible = not S.pick end   -- 这一局里不能换系（阵容跟着这一局）
        -- 局内选车页没有「试驾」（同战雷的出击页；试驾审查 4：局内飞机卡按设计禁选，右边「试驾」还在、点了开的是选中的坦克）——
        --   「只看车」挪到最右边补上空位；局外、匹配中照旧
        if H.testBtn and H.testBtn.Visible == (S.pick == true) then
          H.testBtn.Visible = not S.pick
          if H.viewBtn then H.viewBtn.Position = UDim2.new(1, S.pick and -84 or -174, 0, 108) end
        end
        -- 用户 11-26「那个局内选车的界面别弄科技树了」：底下「科技树」那一条整条收起、开着的科技树关上（整备开着时也收着）
        if H.dock then H.dock.Visible = not S.pick and not H.wsOn end
        if S.pick and G.treeGui and G.treeGui.Visible and closeTree then closeTree() end
        -- 刚进这一局：阵容里先选中匹配时点的那一辆（服务器记的 pickPref）
        if S.pick and S.pickPref and H.lastPref ~= tostring(S.round) .. S.pickPref then
          H.lastPref = tostring(S.round) .. S.pickPref
          for i, k in ipairs(lineupOf(tree.nat)) do
            if k == S.pickPref and selSlot ~= i then
              selSlot = i
              refreshHangar()
            end
          end
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

  ---------------------------------------------------------------- 科技树（E 11-25 照用户发的截图重排：「全部按照这个风格做科技树」）
  --   盖在机库上的一个窗口（底下的出击阵容还看得见）：顶上「科技树 · 系名」、坦克 / 战机、自由研究点、关闭；左边一列国旗；
  --   中间按等级横着排（I 到 VII 一列一列往右），每列里按车种一行一行（主战坦克、第二条线、轻型 / 歼击车、步兵战车、自行防空），同一行前后连线（前置）；
  --   还没开的等级整列盖一层：一把锁 +「再研究 N 辆 X 级车」+ 进度；卡片：车种、战斗等级、车的侧面剪影、名字、研究进度；
  --   点一张卡片：右边出详情（研究 / 购买 / 放进阵容 / 试驾 / 资料卡）
  local WIN_TOP = H.TY + H.TH + 12
  -- 窗口下沿到出击阵容卡片的上沿（盖住阵容上面那行字，卡片还看得见）：720 高的屏幕上坦克树五行不用上下滚
  local panel = frame(root, UDim2.new(1, -2 * M0, 1, -(WIN_TOP + H.winBottom)), UDim2.new(0, M0, 0, WIN_TOP), TH.C.PANEL, 0.04)
  panel.Name = "TechTree"
  panel.Visible = false
  panel.ZIndex = 5
  panel.Active = true   -- 挡住底下的拖动（转车）
  TH.corner(panel)
  TH.stroke(panel, true)
  G.treeGui = panel   -- 测试用
  TH.grad(panel, RGB(34, 39, 44), RGB(12, 14, 17))   -- 11-25「科技树没有设计感」：上亮下暗的一层
  local view = { nat = tree.nat, branch = "ground", sel = nil }
  local HEAD_H = 44
  local top = frame(panel, UDim2.new(1, 0, 0, HEAD_H), nil, TH.C.BG, 0.45)
  frame(top, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 1, -1), TH.C.LINE, 0.8)
  local tFlag = frame(top, UDim2.new(0, 30, 0, 19), UDim2.new(0, 16, 0.5, -9), TH.C.BG, 0)
  tFlag.Name = "TreeFlag"
  local tTitle = text(top, "", UDim2.new(0, 220, 1, 0), UDim2.new(0, 56, 0, 0), TH.S.title, TH.C.TEXT)
  tTitle.Font = TH.F.title
  local tBr = frame(top, UDim2.new(0, 360, 1, 0), UDim2.new(0, 286, 0, 0), nil, 1)   -- 坦克 / 战机 / 直升机三棵树（字 + 下划线的页签）
  local bl = Instance.new("UIListLayout")
  bl.FillDirection = Enum.FillDirection.Horizontal
  bl.SortOrder = Enum.SortOrder.LayoutOrder
  bl.Padding = UDim.new(0, 6)
  bl.Parent = tBr
  local freeT = text(top, "", UDim2.new(0, 260, 1, 0), UDim2.new(1, -320, 0, 0), TH.S.small, DIM, Enum.TextXAlignment.Right)
  freeT.Font = TH.F.mono
  local closeB = button(top, "×", UDim2.new(0, 36, 0, 30), UDim2.new(1, -46, 0, 7))
  closeB.Name = "Close"
  closeB.TextSize = 20
  local tFlags = frame(panel, UDim2.new(0, FLAG_W, 1, -(HEAD_H + 16)), UDim2.new(0, 12, 0, HEAD_H + 10), nil, 1)
  tFlags.Name = "TreeFlags"
  tFlags.Visible = false   -- 11-25 照战雷：国家页签在底下那一条（机库的 Dock）上，这一列不画（按钮还在，测试点得到）
  local DETAIL_W = mobile and 210 or 280
  local scroll = Instance.new("ScrollingFrame")
  scroll.Name = "Grid"
  scroll.Size = UDim2.new(1, -(12 + DETAIL_W + 14), 1, -(HEAD_H + 8))
  scroll.Position = UDim2.new(0, 12, 0, HEAD_H + 4)
  scroll.BackgroundTransparency, scroll.BorderSizePixel = 1, 0
  scroll.ScrollBarThickness = 6
  scroll.ScrollBarImageColor3 = TH.C.MUTE
  scroll.CanvasSize = UDim2.new()
  scroll.ClipsDescendants = true   -- 卷出去的卡片不画到面板外面（Roblox 里卷动框本来就裁，写明白）
  scroll.Parent = panel
  local detail = frame(panel, UDim2.new(0, DETAIL_W, 1, -(HEAD_H + 12)), UDim2.new(1, -DETAIL_W - 6, 0, HEAD_H + 6), TH.C.BG, 0.25)
  detail.Name = "Detail"
  TH.corner(detail)
  local function treeShown(on)   -- 开着科技树：底下的「科技树」把手亮着、箭头朝下，机库中间那一层（乘员、选中的车）让开（整备开着时也让开）
    H.mid.Visible = not on and not H.wsOn
    H.treeOpen = on
    for _, b in ipairs(H.bays or {}) do if b.Parent then b.Visible = on or (G.S ~= nil and G.S.pick == true) end end   -- 阵容卡片的等级底色：科技树开着、局内选车时画
    if H.navTree then
      H.navTree:SetAttribute("Lit", on or nil)
      H.navTree.BackgroundColor3 = on and TH.C.PANEL or TH.C.RAISE
    end
    if H.handleT then H.handleT.Text = (on and "︾  " or "︽  ") .. L("科技树", "Tech tree") .. (on and "  ︾" or "  ︽") end
  end
  -- 关上：原来一下子没了（打开是从下往上滑出来的）——现在先把机库排好，再往下滑出去（Theme.T.out 0.18 秒、Quart Out：docs/style.md
  --   「界面不用 In」）、滑完再藏（11-27「动画做出丝滑感」；先排机库再开始滑：排机库那一帧卡一下不会吃掉动画的开头）。滑的时候又点开：停下来滑回去。
  --   开、关都滑出屏幕（原来只挪 520，16:10 的屏上还剩一两百像素的面板盖着阵容卡，到头「啪」一下没了）
  local TSc = game:GetService("TweenService")
  local SLIDE_OUT = TweenInfo.new((TH.T and TH.T.out) or 0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
  local function offScreen() return UDim2.fromOffset(0, (H.vh or 720) - WIN_TOP + 8) end
  local closing, closeTok, panelHome = false, 0, nil
  H.treeClosing = function() return closing end
  closeTree = function()
    if not panel.Visible or closing then return end
    treeShown(false)
    if hangar.Visible then refreshHangar() end
    if (G.reducedMotion and G.reducedMotion()) or not panelHome or not hangar.Visible then
      panel.Visible = false
      return
    end
    closing = true
    closeTok += 1
    local tok = closeTok
    pcall(function() TSc:Create(panel, SLIDE_OUT, { Position = panelHome + offScreen() }):Play() end)
    task.delay(SLIDE_OUT.Time, function()
      if closeTok ~= tok or not closing then return end
      closing = false
      panel.Visible = false
      panel.Position = panelHome
    end)
  end
  H.closeTree = closeTree
  closeB.MouseButton1Click:Connect(closeTree)

  local CW, CH, GAP, HH = mobile and 150 or 184, mobile and 50 or 58, 8, mobile and 24 or 28   -- 卡宽、卡高、间距、列头高（11-25：左图右字的横条，同战雷）
  local refreshTree
  local function status(it)
    if TT.owned(tree, it.key) then return "own" end
    if TT.researched(tree, it.key) then return "res" end
    if tree.cur[it.nat .. ":" .. it.branch] == it.key then return "cur" end
    if TT.canResearch(tree, it.key) then return "can" end
    return "lock"
  end
  -- 科技树格子：已拥有深绿、研究完没买灰绿、正在研究深琥珀、能研究灰、没解锁更暗（不用蓝：用户 11-21）
  local COL = { own = RGB(40, 80, 52), res = RGB(52, 66, 58), cur = RGB(110, 86, 34), can = RGB(40, 44, 48), lock = RGB(20, 22, 25) }
  -- 一把锁（没开的等级）：弯梁一个圆环、锁身圆角方块、锁眼
  local function drawLock(parent, z)
    local box = frame(parent, UDim2.new(0, 46, 0, 56), UDim2.new(0.5, -23, 0.5, -40), nil, 1)
    box.ZIndex = z
    local sh = frame(box, UDim2.new(0, 30, 0, 36), UDim2.new(0.5, -15, 0, 0), nil, 1)
    sh.ZIndex = z
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = sh
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness = TH.C.MUTE, 5
    s.Parent = sh
    local body = frame(box, UDim2.new(1, 0, 0, 32), UDim2.new(0, 0, 1, -32), TH.C.MUTE, 0)
    body.ZIndex = z + 1
    TH.corner(body, 4)
    local kh = frame(body, UDim2.new(0, 9, 0, 9), UDim2.new(0.5, -4, 0, 8), TH.C.BG, 0)
    kh.ZIndex = z + 2
    local kc = Instance.new("UICorner")
    kc.CornerRadius = UDim.new(0.5, 0)
    kc.Parent = kh
    local ks = frame(body, UDim2.new(0, 4, 0, 10), UDim2.new(0.5, -2, 0, 14), TH.C.BG, 0)
    ks.ZIndex = z + 2
  end

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
  mTitle.Font = Enum.Font.BuilderSansMedium
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
      h.Font = Enum.Font.BuilderSansMedium
    end
    for tier = 1, 4 do
      local open = WM.tierOpen(it, done, tier)
      local sy, oy = py((tier - 1) / 4)
      local rl = text(mGrid, ({ "I", "II", "III", "IV" })[tier], UDim2.new(0, tierW, 0.25, -rowGap - headH / 4), UDim2.new(0, 0, sy, oy), 15, open and WHITE or FAINT, Enum.TextXAlignment.Center)
      rl.Font = Enum.Font.BuilderSansMedium
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
  iTitle.Font = Enum.Font.BuilderSansMedium
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
        local okB, M = pcall(AM.build, AD2, "atk", (airLoad(it)) or AD.presetLoad(AD2))   -- 挂着存的那套（整备）
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
  -- 松开鼠标时指针已经拖出了视口（视口自己的 InputEnded 收不到）：在全局也认一下，别卡在拖动状态
  UIS.InputEnded:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then av.drag = false end
  end)
  RunService.RenderStepped:Connect(function()
    if not infoP.Visible then return end
    -- 不再自己慢慢转（用户 11-27「这里面飞机不要自动旋转了 改为鼠标拖动旋转吧」）：左键 / 手指拖动转、滚轮缩放
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
        -- 飞行物理（用户 11-26 晚「每个飞机要有不同的参数」）：这一型（科技树的版本）自己的重量、推力、翼面积、升力、阻力、过载、失速迎角、
        --   转动惯量、静稳定、操纵方式；下面的转弯是按这些量用能量机动公式算的（1000 米、一半内油 + 两枚中距弹）
        local D = FM and a.kind == "jet" and (FM.get(a.id, it.key) or FM.get(a.like or ""))
        if D then
          local c = FM.card(D)
          local dg = 180 / math.pi
          local fcsName = ({ fbw = L("数字 / 模拟电传", "fly-by-wire"), cas = L("机械 + 控制增强", "mechanical + CAS"), mech = L("机械操纵", "mechanical") })[D.fcs] or D.fcs
          add(L("飞行物理", "Flight physics"), WHITE, 15)
          add(L("平飞最大速度 ", "Top speed ") .. math.floor(FM.vTop(D, c.m, 100) * 3.6 + 0.5) .. ((D.Ta > D.Tm) and (" / " .. math.floor(FM.vTop(D, c.m, 130) * 3.6 + 0.5)) or "")
            .. L(" km/h（军推 / 加力，1000 米）", " km/h (mil / AB, 1000 m)"), DIM, 12)
          add(L("作战重量 ", "Combat weight ") .. math.floor(c.m / 10 + 0.5) * 10 .. " kg" .. L("（空重 ", " (empty ") .. D.m0 .. L("，满内油 ", ", int. fuel ") .. D.fi .. "）", DIM, 12)
          add(L("推力 ", "Thrust ") .. math.floor(D.Tm / 100 + 0.5) / 10 .. ((D.Ta > D.Tm) and (" / " .. math.floor(D.Ta / 100 + 0.5) / 10 .. L(" 千牛（军推 / 加力）", " kN (mil / AB)")) or L(" 千牛", " kN"))
            .. L(" · 推重比 ", " · T/W ") .. string.format("%.2f", c.tw), DIM, 12)
          add(L("翼面积 ", "Wing area ") .. D.S .. " m²" .. L(" · 翼载 ", " · loading ") .. math.floor(c.wl + 0.5) .. " kg/m²" .. L(" · 展弦比 ", " · AR ") .. string.format("%.1f", D.AR), DIM, 12)
          add(L("最大升力系数 ", "CLmax ") .. string.format("%.2f", D.CLm) .. L(" · 失速迎角 ", " · stall AoA ") .. D.aS .. "°" .. (D.aL and (L(" · 迎角限制 ", " · AoA limit ") .. D.aL .. "°") or ""), DIM, 12)
          add(L("零升阻力 ", "CD0 ") .. string.format("%.4f", D.CD0) .. L(" · 诱导阻力因子 ", " · K ") .. string.format("%.3f", D.Kc) .. L(" · 波阻峰值 ", " · wave ") .. string.format("%.3f", D.CDw), DIM, 12)
          add(L("过载 ", "G limits ") .. D.nzN .. " / +" .. D.nzP .. " g" .. L(" · 最大滚转 ", " · roll ") .. D.pmax .. "°/s", DIM, 12)
          local mI = c.m
          add(L("转动惯量 ", "Inertia ") .. string.format("%.0f / %.0f / %.0f", mI * D.rx2 / 1000, mI * D.ry2 / 1000, mI * D.rz2 / 1000) .. L(" 吨·米²（滚 / 俯 / 偏）", " t·m² (roll/pitch/yaw)"), DIM, 12)
          add(L("静稳定裕度 ", "Static margin ") .. string.format("%+.0f%%", D.sm * 100) .. (D.sm < 0 and L("（放宽静稳定）", " (relaxed)") or "") .. L(" · 操纵 ", " · controls ") .. fcsName
            .. (D.tvc and L(" · 推力矢量", " · thrust vectoring") or ""), DIM, 12)
          add(L("持续转弯 ", "Sustained turn ") .. string.format("%.1f°/s", c.str * dg) .. (c.strV and string.format(" @ %d km/h", math.floor(c.strV * 3.6 + 0.5)) or "")
            .. L(" · 瞬时转弯 ", " · instant. ") .. string.format("%.1f°/s", c.itr * dg), DIM, 12)
        end
        -- 当前挂载（整备里存的那套，没存过是第一套预设）：武器、内油；外挂重量、阻力增量用飞行物理同一套算（FlightModel.loadout）
        local cl, cpk, cf = airLoad(it)
        local pName = cpk and T2("preset." .. cpk) or nil
        add(L("当前挂载", "Current loadout") .. ((pName and pName ~= "preset." .. cpk) and ("  ·  " .. pName) or ""), WHITE, 15)
        local okG, list = pcall(AD.groups, a, cl or AD.presetLoad(a))
        for _, wid in ipairs(okG and list or {}) do add("   " .. T2("aw." .. wid), DIM, 12) end
        if FM and FM.loadout and cl then
          local okL, Lo = pcall(FM.loadout, a, cl, cf, { key = it.key, AD = AD })
          if okL and Lo then
            add(L("内油 ", "Internal fuel ") .. math.floor(cf * 100 + 0.5) .. "%" .. L(" · 外挂 ", " · stores ") .. math.floor(Lo.ext + 0.5) .. " kg"
              .. (Lo.dCD0 and (L(" · 阻力 ΔCD0 +", " · drag ΔCD0 +") .. string.format("%.4f", Lo.dCD0)) or ""), DIM, 12)
          end
        end
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
    if (last.coins or 0) > 0 then table.insert(parts, L("金币 +", "Coins +") .. fmtNum(last.coins)) end   -- 11-26 金币不再无限：这一局挣了多少
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
    if not it then
      local t = text(detail, L("点一张卡片看详情：研究、购买、放进出击阵容、试驾", "Select a vehicle to research, buy, add to the lineup or test drive"),
        UDim2.new(1, -24, 0, 60), UDim2.new(0, 12, 0, 12), TH.S.small, FAINT)
      t.TextWrapped, t.TextTruncate = true, Enum.TextTruncate.None
      t.TextYAlignment = Enum.TextYAlignment.Top
      return
    end
    -- 上面一块大车图（同卡片的渐变底板）
    local bay = frame(detail, UDim2.new(1, -16, 0, 130), UDim2.new(0, 8, 0, 8), RGB(255, 255, 255), 0.42)
    bay.Name = "DetailBay"
    TH.corner(bay, 2)
    TH.rankGrad(bay, it.rank)
    local big = Instance.new("ImageLabel")
    big.Name = "DetailPic"
    big.BackgroundTransparency = 1
    big.ScaleType = Enum.ScaleType.Fit
    big.Size, big.Position = UDim2.new(1, -8, 1, -8), UDim2.new(0, 4, 0, 4)
    big.Parent = bay
    picOn(big, it)
    local y = 146
    local function line(str, ts, col, h)
      local t = text(detail, str, UDim2.new(1, -24, 0, h or 20), UDim2.new(0, 12, 0, y), ts or TH.S.small, col or DIM)
      t.TextWrapped = true
      y += (h or 20) + 4
      return t
    end
    line(nm(it), TH.S.title, WHITE, 26).Font = TH.F.title
    line((zh and it.en or it.name) .. " · " .. it.year, 13, DIM)
    line(L("等级 ", "Rank ") .. TT.RANKS[it.rank].roman .. "（" .. TT.RANKS[it.rank].years .. "）· " .. L("战斗等级 ", "BR ") .. TT.brText(it.br), 13, DIM)
    local stt = status(it)
    local stName = ({ own = L("已买下", "Owned"), res = L("已研究，可以买", "Researched"), cur = L("正在研究", "Researching"),
      can = L("可以研究", "Can research"), lock = L("还没开（先研究前一辆 / 上一级）", "Locked") })[stt]
    line(stName, 14, WHITE)
    if stt ~= "own" and stt ~= "res" then
      line(L("研究点 ", "RP ") .. tostring(tree.rp[it.key] or 0) .. " / " .. it.rp, 13, DIM)
    end
    if stt ~= "own" then line(L("价钱 ", "Cost ") .. it.cost .. L(" 金币", " coins"), 13, DIM) end
    if it.stand then
      local base = it.base and (VD.get(it.base) or AD.get(it.base)) and it.base or "?"
      line(L("还没有自己的模型：暂用 ", "No model yet: uses ") .. vname(base) .. L(" 的模型和性能", "'s model & stats"), 12, RGB(200, 170, 90), 34)
    elseif it.model then
      line(L("模型暂用同族的 ", "Model from ") .. vname(it.model) .. L("；炮、弹、装甲、机动按本车", "; gun, ammo, armour and mobility are its own"), 12, RGB(170, 185, 150), 34)
    end
    y += 8
    local function btn(str, primary, f)
      local b = button(detail, str, UDim2.new(1, -24, 0, 38), UDim2.new(0, 12, 0, y), primary)
      b.MouseButton1Click:Connect(f)
      y += 46
      return b
    end
    btn(L("资料卡 · 装甲", "Stats · armor"), false, function() openInfo(it) end).Name = "InfoBtn"
    -- 试驾：随便哪一辆都能试（服务器 Tech.lua testDrive：东边单独一块场地、三辆靶车、改装全装；下车回机库）
    btn(L("试驾", "Test drive"), false, function()
      closeTree()
      act("testDrive", it.key)
    end).Name = "TestBtn"
    if stt == "can" then
      btn(L("研究这一辆", "Research"), true, function() act("treeResearch", it.key) end).Name = "Research"
    elseif stt == "res" then
      -- 金币不够（用户 11-26「金币不要设置成无限」）：按钮写还差多少、不是主按钮（点了服务器也会说差多少）
      local coins = me:GetAttribute("Coins")
      local short = (me:GetAttribute("CoinsInf") ~= true and type(coins) == "number") and (it.cost - coins) or 0
      local bb = btn(short > 0 and (L("金币不够（还差 ", "Not enough coins (") .. fmtNum(short) .. L("）", " short)")) or (L("购买（", "Buy (") .. fmtNum(it.cost) .. ")"),
        short <= 0, function() act("treeBuy", it.key) end)
      bb.Name = "Buy"
      if short > 0 then bb:SetAttribute("Short", short) end
    elseif stt == "own" then
      local md = tree.mods and tree.mods[it.key]
      local nDone, nAll = WM.count(it, md and md.done)
      btn(L("改装（", "Modifications (") .. nDone .. " / " .. nAll .. L("）", ")"), false, function() openMods(it) end).Name = "ModsBtn"
      local L0 = table.clone(lineupOf(it.nat))
      local idx = table.find(L0, it.key)
      if idx then
        btn(L("移出出击阵容", "Remove from lineup"), false, function()
          table.remove(L0, idx)
          act("treeLineup", it.nat, L0)
        end).Name = "LineupOut"
      elseif (it.branch == "air" or it.branch == "heli") and (function()
          local n = 0
          for _, k in ipairs(L0) do local x = TT.get(k) if x and (x.branch == "air" or x.branch == "heli") then n += 1 end end
          return n >= 2
        end)() then
        line(L("出击阵容里最多带两个飞行单位：先移出一架", "At most two aircraft in the lineup"), 12, DIM)   -- 用户 11-25「最多两个飞行单位」
      elseif #L0 < 5 then
        btn(L("放进出击阵容", "Add to lineup"), true, function()
          table.insert(L0, it.key)
          act("treeLineup", it.nat, L0)
        end).Name = "LineupIn"
      else
        line(L("出击阵容满了（5 辆）：先移出一辆", "Lineup full (5)"), 12, DIM)
      end
    end
  end
  refreshTree = function()
    local N = TT.NAT[view.nat]
    tTitle.Text = L("科技树", "Tech tree") .. "  ·  " .. (zh and N.name or N.en)
    clear(tFlag)
    drawFlag(tFlag, view.nat)
    flagStrip(tFlags, view.nat, function(nat)
      view.nat = nat
      view.sel = nil
      if nat ~= tree.nat then   -- 科技树里换系，机库也跟着换（机库里不再有国旗栏）
        tree.nat = nat
        selSlot = 1
        act("treeNat", nat)
      end
      refreshTree()
    end, FLAG_W)
    clear(tBr)
    for i, br in ipairs(TT.BRANCHES) do
      local B0 = TT.BRANCH[br]
      local on = br == view.branch
      local b = Instance.new("TextButton")
      b.Name = "Br_" .. br
      b.LayoutOrder = i
      b.AutoButtonColor, b.BackgroundTransparency = false, 1
      b.Size = UDim2.new(0, 100, 1, 0)
      b.Text, b.Font, b.TextSize = zh and B0.name or B0.en, on and TH.F.bold or TH.F.body, TH.S.sub
      b.TextColor3 = on and TH.C.TEXT or TH.C.MUTE
      b.Parent = tBr
      if on then frame(b, UDim2.new(1, -24, 0, 3), UDim2.new(0, 12, 1, -4), AMBER, 0) end
      b.MouseEnter:Connect(function() if not on then b.TextColor3 = TH.C.TEXT end end)
      b.MouseLeave:Connect(function() if not on then b.TextColor3 = TH.C.MUTE end end)
      b.MouseButton1Click:Connect(function() view.branch = br view.sel = nil refreshTree() end)
    end
    freeT.Text = L("自由研究点 ", "Free RP ") .. tostring(tree.free[view.nat] or 0)
    clear(scroll)
    local B = TT.BRANCH[view.branch]
    local list = TT.list[view.nat][view.branch]
    -- 11-25 照战雷排（用户发的截图）：等级从上往下一行一行（I 级在最上），车种一列一列（主战坦克、第二条线……），
    --   同一列里前后用竖线连着；一张卡片左边是写实车图、右边名字和战斗等级；还没开的等级整行盖一层锁
    local nCols = #B.cols
    local GUT = mobile and 52 or 64   -- 左边等级那一栏
    local per = {}
    for _, it in ipairs(list) do
      per[it.col] = per[it.col] or {}
      per[it.col][it.rank] = (per[it.col][it.rank] or 0) + 1
    end
    local colX, colW, x = {}, {}, GUT
    for c = 1, nCols do
      local m = 1
      for _, n in pairs(per[c] or {}) do if n > m then m = n end end
      colX[c], colW[c] = x, m * (CW + GAP) + GAP
      x += colW[c]
    end
    -- 行高：这一级这棵树没有车（没找到原模型的删掉了，11-25）收成一条窄的，不留一大片空白
    local inRank = {}
    for _, it in ipairs(list) do inRank[it.rank] = (inRank[it.rank] or 0) + 1 end
    local rowY, rowHs, y = {}, {}, HH
    local rowH = CH + 2 * GAP + (mobile and 8 or 12)
    for r = 1, #TT.RANKS do
      rowY[r], rowHs[r] = y, ((inRank[r] or 0) > 0 or #list == 0) and rowH or 30
      y += rowHs[r]
    end
    local totalH = y
    -- 列头：车种名
    for c = 1, nCols do
      local cn = B.cols[c] or { "", "" }
      local h = text(scroll, zh and cn[1] or cn[2], UDim2.new(0, colW[c] - 8, 0, HH - 6), UDim2.new(0, colX[c] + 4, 0, 2), TH.S.body, TH.C.MUTE, Enum.TextXAlignment.Center)
      h.Font = TH.F.bold
      h.ZIndex = 2
    end
    -- 行：底色深浅交替，左边「I 级」+ 年代
    for r = 1, #TT.RANKS do
      -- 每一级一种底色（Theme.RANK），左边那一栏（等级数字）颜色更实，往右淡开
      local band = frame(scroll, UDim2.new(0, x - 2, 0, rowHs[r] - 2), UDim2.new(0, 0, 0, rowY[r]), TH.rankColor(r), 0.72)
      band.Name = "Rank_" .. r
      band.ZIndex = 1
      do
        local g = Instance.new("UIGradient")
        g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(math.min(0.3, GUT / math.max(x, 1) * 1.6), 0.35), NumberSequenceKeypoint.new(1, 0.6) })
        g.Parent = band
      end
      frame(band, UDim2.new(1, 0, 0, 1), nil, TH.C.LINE, 0.88).ZIndex = 2   -- 每一级顶上一道细线
      if rowHs[r] < rowH then   -- 窄条：一行写完
        local h = text(band, TT.RANKS[r].roman .. L(" 级 · ", " · ") .. TT.RANKS[r].years .. L(" · 这一级暂无载具", " · no vehicles"), UDim2.new(1, -16, 1, 0), UDim2.new(0, 8, 0, 0), TH.S.small, FAINT)
        h.Font = TH.F.cond
        h.ZIndex = 2
      else
        local h = text(band, TT.RANKS[r].roman, UDim2.new(0, GUT - 8, 0, 30), UDim2.new(0, 8, 0, 6), TH.S.big, TH.C.TEXT)
        h.Font = TH.F.title
        h.TextTransparency = 0.25
        h.ZIndex = 2
        local yr = text(band, L("级 · ", "") .. TT.RANKS[r].years, UDim2.new(0, GUT - 6, 0, 14), UDim2.new(0, 8, 0, 38), TH.S.tiny, FAINT)
        yr.Font = TH.F.cond
        yr.ZIndex = 2
      end
    end
    if #list == 0 then   -- 这棵树一项都没有（11-25 没有原模型的都删了，德国固定翼一架也没找到）
      local e = text(scroll, L("这棵树还没有找到能用的原模型，找到了再加上", "No vehicles with original models in this tree yet"),
        UDim2.new(0, 560, 0, 24), UDim2.new(0, GUT + 16, 0, HH + 16), TH.S.body, DIM)
      e.Name = "Empty"
      e.ZIndex = 5
    end
    -- 卡片
    local used, pos = {}, {}
    for _, it in ipairs(list) do
      used[it.col] = used[it.col] or {}
      local k = used[it.col][it.rank] or 0
      used[it.col][it.rank] = k + 1
      local cx, cy = (colX[it.col] or GUT) + GAP + k * (CW + GAP), (rowY[it.rank] or HH) + GAP + (mobile and 4 or 6)
      pos[it.key] = { x = cx, y = cy }
      local stt = status(it)
      local lock = stt == "lock"
      local sel = view.sel == it.key
      local card = Instance.new("TextButton")
      card.Name = "Card_" .. it.key
      card.AutoButtonColor = true
      card.Text = ""
      card.Size, card.Position = UDim2.new(0, CW, 0, CH), UDim2.new(0, cx, 0, cy)
      -- 卡片（11-25「科技树没有设计感」）：深色底 + 左边一道状态色条（已拥有绿、研究完淡绿、正在研究琥珀、能研究白、没开灰），
      --   车图放在一块上亮下暗的底板上；名字窄体粗字靠右、战斗等级等宽字在右下；选中琥珀描边，鼠标放上去底色亮一点
      -- 用户 11-26「车辆那个跟等级挂钩的背景颜色改成覆盖整个车辆的方框」：整张卡的底色就是这一级的颜色（上亮下暗的渐变），
      --   锁住的整张压暗；车图下面垫一块半透明的深色（车图、字都清楚）
      local BASE = lock and RGB(120, 120, 120) or Color3.new(1, 1, 1)
      card.BackgroundColor3, card.BackgroundTransparency, card.BorderSizePixel = BASE, 0, 0
      TH.rankGrad(card, it.rank)
      card.AutoButtonColor = false
      card.ZIndex = 3
      card.Parent = scroll
      TH.corner(card, 3)
      if sel then TH.glow(card) else TH.stroke(card, false, TH.C.LINE).Transparency = 0.86 end
      local STRIP = ({ own = TH.C.GOOD, res = RGB(120, 170, 126), cur = AMBER, can = TH.C.TEXT, lock = RGB(70, 74, 78) })[stt]
      local strip = frame(card, UDim2.new(0, 3, 1, -6), UDim2.new(0, 3, 0, 3), STRIP, (stt == "can") and 0.45 or 0)
      strip.ZIndex = 5
      TH.corner(strip, 1)
      local bay = frame(card, UDim2.new(0, math.floor(CW * 0.56), 1, -6), UDim2.new(0, 9, 0, 3), RGB(0, 0, 0), lock and 0.55 or 0.7)
      bay.Name = "Bay"
      bay.ZIndex = 3
      TH.corner(bay, 2)
      card.MouseEnter:Connect(function() card.BackgroundColor3 = lock and RGB(160, 160, 160) or RGB(255, 255, 255) end)
      card.MouseLeave:Connect(function() card.BackgroundColor3 = BASE end)
      local img = Instance.new("ImageLabel")   -- 左边：写实车图（没有才是白色剪影）
      img.Name = "Pic"
      img.BackgroundTransparency = 1
      img.ScaleType = Enum.ScaleType.Fit
      img.Size, img.Position = UDim2.new(0, math.floor(CW * 0.56), 1, -6), UDim2.new(0, 9, 0, 3)
      img.ImageColor3 = (stt == "own") and TH.C.TEXT or (lock and FAINT or DIM)
      img.ImageTransparency = lock and 0.45 or 0.1
      img.ZIndex = 4
      img.Parent = card
      picOn(img, it)
      if img:GetAttribute("Photo") then
        img.ImageTransparency = lock and 0.35 or 0
        img.ImageColor3 = lock and RGB(120, 120, 120) or Color3.new(1, 1, 1)
      end
      local n1 = text(card, nm(it), UDim2.new(0.44, -14, 0, 34), UDim2.new(0.56, 8, 0, 4), mobile and TH.S.small or TH.S.body, lock and FAINT or TH.C.TEXT, Enum.TextXAlignment.Right)
      n1.Font = TH.F.bold
      n1.TextWrapped, n1.TextTruncate, n1.TextYAlignment = true, Enum.TextTruncate.AtEnd, Enum.TextYAlignment.Top
      n1.ZIndex = 4
      local brL = text(card, TT.brText(it.br), UDim2.new(0.44, -14, 0, 16), UDim2.new(0.56, 8, 1, -20), TH.S.body, lock and FAINT or TH.C.TEXT, Enum.TextXAlignment.Right)
      brL.Font = TH.F.mono
      local brTag = text(card, "BR", UDim2.new(0, 20, 0, 12), UDim2.new(1, -62, 1, -18), TH.S.tiny, FAINT, Enum.TextXAlignment.Right)
      brTag.Font = TH.F.cond
      brTag.ZIndex = 4
      brL.ZIndex = 4
      if stt == "cur" or (tree.rp[it.key] or 0) > 0 then   -- 研究进度：卡片底边一道琥珀
        local bg = frame(card, UDim2.new(1, -4, 0, 3), UDim2.new(0, 2, 1, -4), RGB(30, 30, 30), 0)
        bg.ZIndex = 5
        local fill = frame(bg, UDim2.new(math.clamp((tree.rp[it.key] or 0) / it.rp, 0, 1), 0, 1, 0), nil, GOLD, 0)
        fill.ZIndex = 6
      end
      card.MouseButton1Click:Connect(function()
        view.sel = it.key
        refreshTree()
      end)
    end
    -- 同一列前后连线：前置的下沿 → 这一张的上沿（前置研究完的亮、没研究的暗）
    for _, it in ipairs(list) do
      local a, b = it.prev and pos[it.prev], pos[it.key]
      if a and b and b.y > a.y + CH then
        local x0 = math.min(a.x, b.x) + CW / 2
        local col = TT.researched(tree, it.prev) and DIM or RGB(56, 60, 64)
        local arrow = text(scroll, "▼", UDim2.new(0, 14, 0, 10), UDim2.new(0, b.x + CW / 2 - 7, 0, b.y - 10), 10, col, Enum.TextXAlignment.Center)
        arrow.ZIndex = 2
        if math.abs(a.x - b.x) < 1 then
          local ln = frame(scroll, UDim2.new(0, 2, 0, b.y - (a.y + CH) - 6), UDim2.new(0, a.x + CW / 2 - 1, 0, a.y + CH), col, 0)
          ln.ZIndex = 2
        else   -- 同一格里排在后面的：先往下再横过去
          local my = a.y + CH + (b.y - a.y - CH) / 2
          frame(scroll, UDim2.new(0, 2, 0, my - (a.y + CH)), UDim2.new(0, a.x + CW / 2 - 1, 0, a.y + CH), col, 0).ZIndex = 2
          frame(scroll, UDim2.new(0, math.abs(b.x - a.x) + 2, 0, 2), UDim2.new(0, x0 - 1, 0, my - 1), col, 0).ZIndex = 2
          frame(scroll, UDim2.new(0, 2, 0, b.y - my), UDim2.new(0, b.x + CW / 2 - 1, 0, my), col, 0).ZIndex = 2
        end
      end
    end
    -- 还没开的等级：整行盖一层，一把锁 +「再研究 N 辆 X 级车」+ 进度（上一级研究完几辆 / 要几辆）
    for r = 2, #TT.RANKS do
      if (inRank[r] or 0) > 0 and not TT.rankOpen(tree, view.nat, view.branch, r) then
        -- 要几辆按服务器同一条规则（TT.rankNeed：上一级车不够数的按有几辆算，上一级没车再往上看）
        local have, need, pr = TT.rankNeed(tree, view.nat, view.branch, r)
        -- 半透明的一层（车还看得见、压暗），右头写还差几辆（同战雷：没开的等级灰着）
        local cover = frame(scroll, UDim2.new(0, x - GUT - 2, 0, rowHs[r] - 2), UDim2.new(0, GUT, 0, rowY[r]), TH.C.BG, 0.45)
        cover.Name = "Locked_" .. r
        cover.ZIndex = 7
        local t1 = text(cover, L("未解锁 · 再研究 ", "Locked · research ") .. math.max(0, need - have) .. L(" 辆 ", " more rank ") .. TT.RANKS[pr].roman .. L(" 级车（", " (") .. have .. " / " .. need .. L("）", ")"),
          UDim2.new(0, 460, 0, 14), UDim2.new(0, 8, 0, 0), TH.S.tiny, TH.C.TEXT, Enum.TextXAlignment.Left)   -- 左上角（右头常常卷在看不见的地方）
        t1.Font = TH.F.bold
        t1.ZIndex = 8
        t1.TextStrokeTransparency = 0.4
      end
    end
    scroll.CanvasSize = UDim2.new(0, x + 8, 0, totalH + 8)
    G.treeLayout = { cols = colX, rows = rowY }   -- 测试用：等级是行、车种是列
    showDetail(view.sel and TT.get(view.sel))
  end
  -- 点底下的「科技树」：从下往上弹出来（同战雷），停在顶栏下面、底下那一条上面
  local TS = game:GetService("TweenService")
  local panelPos = panel.Position
  panelHome = panelPos
  openTree = function()
    view.nat = tree.nat
    local back = closing   -- 正在往下滑着关：从现在的位置滑回去
    if closing then
      closing = false
      closeTok += 1
    end
    local was = panel.Visible and not back
    panel.Visible = true
    treeShown(true)
    refreshTree()
    if not was then
      if G.reducedMotion and G.reducedMotion() then   -- 「减少动态效果」：跟关的时候一样直接出来
        panel.Position = panelPos
      else
        if not back then panel.Position = panelPos + offScreen() end
        pcall(function() TS:Create(panel, TweenInfo.new((TH.T and TH.T.panel) or 0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = panelPos }):Play() end)
      end
    end
  end
  -- 底下换了国家（科技树开着）：科技树跟着换
  G.treeView = function(nat)
    view.nat = nat
    view.sel = nil
    if panel.Visible then refreshTree() end
  end
  G.openTechTree = openTree
  G.refreshTechTree = function() if panel.Visible then refreshTree() end end

  -- 金币变了（买了车、一局结算）：科技树开着的话详情里的「购买 / 金币不够」跟着变
  me:GetAttributeChangedSignal("Coins"):Connect(function()
    if panel.Visible then showDetail(view.sel and TT.get(view.sel)) end
  end)
  me:GetAttributeChangedSignal("Tree"):Connect(function()
    readTree()
    if panel.Visible then refreshTree() end
    if modsP.Visible then refreshMods() end
    if crewP.Visible then refreshCrew() end
    if hangar.Visible then refreshHangar() end
  end)
end

return TechUI
