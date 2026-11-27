-- Roblox全面大战场（客户端）——战雷式坦克界面（用户 11-24 夜「把整个游戏做成战雷」②：坦克战雷化）
--   电脑上开坦克时 VehHud 的 stepTank 每帧调 G.wtTankStep，原来 MWT 那套（右下全息车、六边形弹种钮、∧ 准星、车旁的车速牌）收起：
--   · 准星：炮现在指的地方一个圆（中心一点、左右下三道刻度），颜色就是战雷的穿深指示——照服务器 Wt.lua 同一套算
--     （WtDamage：瞄着的那一处几毫米、入射角换算的等效厚度、这种弹在这个距离的穿深、跳弹概率）：
--     绿 打得穿，黄 说不准（穿深和等效厚度差不多、或者可能跳弹），红 打不穿 / 会跳弹，没瞄着敌方车辆是白的；
--     圈外一道装填弧（顺时针走满就装好），左边剩几秒、右边测距
--   · 底部正中：弹药栏——主炮每种弹一格（数字键直接选，战雷那样）、机炮 / 机枪各一格，烟幕弹（X）、维修 / 灭火（Y）；
--     选中的白框，装填中这一格从下往上亮起来、写剩几秒；打光了数字变红
--   · 左下（圆形小地图右边）：损伤示意图——俯视的车（车头朝上）：车体轮廓、履带、发动机、传动、弹药架、油箱，
--     炮塔跟着炮塔朝向转（炮管、炮闩、方向机、尾舱弹药在炮塔上）；乘员一个个小人在自己的位子上（白 好、橙 伤、灰 阵亡 / 空位）；
--     模块好的淡灰、受损黄、损毁红，刚坏的闪一下，起火的地方一团火；右边车速、档位，起火 / 维修中 / 按 Y 修的提示
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local WtTank = {}

function WtTank.init(G)
  local W = require(RS:WaitForChild("WtDamage"))
  local VD = require(RS:WaitForChild("VehDefs"))
  local BAL = require(RS:WaitForChild("Ballistics"))
  local TM = require(RS:WaitForChild("TankMods"))   -- 爆反种类（穿深指示扣爆反，同服务器 Era.lua）
  local V2, UD2 = Vector2.new, UDim2.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local BOLD, MED = Enum.Font.BuilderSansBold, Enum.Font.BuilderSansMedium
  local MONO_F = Enum.Font.RobotoMono
  local LEFT, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right
  local TH = G.Theme   -- 统一外观（docs/style.md）
  local WHITE, INK = TH.C.TEXT, TH.C.INK
  local PEN_OK, PEN_MAYBE, PEN_NO = TH.C.GOOD, TH.C.WARN, TH.C.BAD
  local AMBER = TH.C.WARN
  local M_OK, M_HURT, M_DEAD = TH.C.NEUTRAL, TH.C.WARN, TH.C.BAD
  local C_OK, C_HURT, C_DEAD = TH.C.TEXT, TH.C.WARN, TH.C.FAINT

  local gui = Instance.new("ScreenGui")
  gui.Name = "WtTank"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 5
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")

  local function frame(parent, size, pos, color, tr, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position, f.AnchorPoint = size, pos or UD2(), anchor or V2()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = color or WHITE, tr or 0, 0
    f.Parent = parent
    return f
  end
  local function label(parent, text, size, pos, ts, color, font, anchor, align)
    local l = Instance.new("TextLabel")
    l.Size, l.Position, l.AnchorPoint = size, pos or UD2(), anchor or V2()
    l.BackgroundTransparency = 1
    l.Text, l.TextSize, l.TextColor3, l.Font = text or "", ts or 13, color or WHITE, font or BOLD
    l.TextXAlignment = align or Enum.TextXAlignment.Center
    l.TextStrokeTransparency, l.TextStrokeColor3 = 0.45, INK   -- 沙地、天空这种亮背景上也看得清
    l.Parent = parent
    return l
  end
  local function round(f, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = r or UDim.new(0.5, 0)
    c.Parent = f
    return f
  end
  local function stroke(f, color, th, tr)
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = color, th, tr or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = f
    return s
  end
  local function nk(t, v) return NumberSequenceKeypoint.new(t, v) end

  -- 平滑的进度弧（顺时针、从正上方起）：左右两半各裁一半，各自一个圆环描边，描边上的渐变一半透明、转渐变的角度就是走到哪
  --   （Roblox 没有画弧线的东西；转了角度的细方块拼的弧边缘有锯齿——用户 11-19 嫌像素感）
  local function progRing(parent, D, th, color)
    local o = { root = frame(parent, UD2(0, D, 0, D), UD2(0.5, 0, 0.5, 0), WHITE, 1, V2(0.5, 0.5)), g = {}, s = {} }
    for i = 1, 2 do   -- 1 右半、2 左半
      local clip = frame(o.root, UD2(0.5, 0, 1, 0), UD2(i == 1 and 0.5 or 0, 0, 0, 0), WHITE, 1)
      clip.ClipsDescendants = true
      local ring = round(frame(clip, UD2(2, -2 * th, 1, -2 * th), UD2(i == 1 and -1 or 0, th, 0, th), WHITE, 1))
      local s = stroke(ring, color, th, 0)
      local g = Instance.new("UIGradient")
      g.Transparency = NumberSequence.new({ nk(0, 0), nk(0.499, 0), nk(0.501, 1), nk(1, 1) })
      g.Parent = s
      o.g[i], o.s[i] = g, s
    end
    function o.set(k, col)
      local a = math.clamp(k, 0, 1) * 360
      -- 渐变方向转 a 度：方向反面那半个平面不透明——右半从正上方顺时针走到 a，过了半圈左半接着走
      o.g[1].Rotation = math.clamp(a, 0, 180)
      o.g[2].Rotation = math.clamp(a, 180, 360)
      if col then for _, s in ipairs(o.s) do s.Color = col end end
    end
    return o
  end

  ---------------------------------------------------------------- 准星（炮指的地方）
  local AIM = {}
  AIM.root = frame(gui, UD2(0, 90, 0, 90), UD2(0.5, 0, 0.5, 0), WHITE, 1, V2(0.5, 0.5))
  AIM.root.Name = "WtGunAim"
  AIM.scale = Instance.new("UIScale")
  AIM.scale.Parent = AIM.root
  -- 黑色的底：每一道白线后面垫一道半透明黑（亮沙地上白线会看不见）
  stroke(round(frame(AIM.root, UD2(0, 25, 0, 25), UD2(0.5, 0, 0.5, 0), WHITE, 1, V2(0.5, 0.5))), INK, 3.4, 0.62)
  AIM.ring = round(frame(AIM.root, UD2(0, 25, 0, 25), UD2(0.5, 0, 0.5, 0), WHITE, 1, V2(0.5, 0.5)))
  AIM.ringS = stroke(AIM.ring, WHITE, 1.6, 0.02)
  AIM.ticks = {}
  for _, e in ipairs({ { -1, 0 }, { 1, 0 }, { 0, 1 } }) do   -- 左、右、下三道刻度
    local hz = e[1] ~= 0
    local pos = UD2(0.5, e[1] * 21, 0.5, e[2] * 21)
    frame(AIM.root, hz and UD2(0, 10, 0, 4) or UD2(0, 4, 0, 10), pos, INK, 0.62, V2(0.5, 0.5))
    table.insert(AIM.ticks, frame(AIM.root, hz and UD2(0, 8, 0, 2) or UD2(0, 2, 0, 8), pos, WHITE, 0.02, V2(0.5, 0.5)))
  end
  stroke(round(frame(AIM.root, UD2(0, 3, 0, 3), UD2(0.5, 0, 0.5, 0), WHITE, 1, V2(0.5, 0.5))), INK, 1, 0.5)
  AIM.dot = round(frame(AIM.root, UD2(0, 3, 0, 3), UD2(0.5, 0, 0.5, 0), WHITE, 0, V2(0.5, 0.5)))
  -- 炮口被挡（用户 11-27「坦克准心对标战雷」）：炮塔转到位了，这一发却会打在前面的坡 / 墙上——圈里画一个叉（Drive gunImpact 判的）
  AIM.block = frame(AIM.root, UD2(0, 20, 0, 20), UD2(0.5, 0, 0.5, 0), WHITE, 1, V2(0.5, 0.5))
  AIM.block.Name = "WtGunBlocked"
  AIM.block.Visible = false
  for _, r in ipairs({ 45, -45 }) do
    local b = frame(AIM.block, UD2(0, 18, 0, 2), UD2(0.5, 0, 0.5, 0), PEN_NO, 0, V2(0.5, 0.5))
    b.Rotation = r
  end
  -- 装填弧：圈外一道大环（用户 11-25「坦克开炮后外面那个大环装弹是顺时针从红色变成绿色」）——从正上方顺时针走满，
  --   颜色跟着进度从红经琥珀变绿，装好那一下整圈绿亮一下再收；底下一道很淡的轨道
  AIM.track = stroke(round(frame(AIM.root, UD2(0, 48, 0, 48), UD2(0.5, 0, 0.5, 0), WHITE, 1, V2(0.5, 0.5))), INK, 3, 0.7)
  AIM.rel = progRing(AIM.root, 54, 3, PEN_NO)
  AIM.relT = label(AIM.root, "", UD2(0, 50, 0, 14), UD2(0.5, -36, 0.5, 0), 14, AMBER, BOLD, V2(1, 0.5), RIGHT)
  AIM.rng = label(AIM.root, "", UD2(0, 70, 0, 14), UD2(0.5, 36, 0.5, 0), 14, WHITE, BOLD, V2(0, 0.5), LEFT)
  local function relColor(k)   -- 装填进度 → 红 → 琥珀 → 绿
    k = math.clamp(k or 0, 0, 1)
    if k < 0.5 then return PEN_NO:Lerp(AMBER, k / 0.5) end
    return AMBER:Lerp(PEN_OK, (k - 0.5) / 0.5)
  end
  local readyT, wasReady = -9, true

  ---------------------------------------------------------------- 穿深指示：照服务器（Wt.lua G.wtShellHit）同一套算
  local rayP = RaycastParams.new()
  rayP.FilterType = Enum.RaycastFilterType.Exclude
  local function entOf(inst)
    local ents = workspace:FindFirstChild("Ents")
    while inst and inst.Parent and inst.Parent ~= ents do inst = inst.Parent end
    return (inst and inst.Parent == ents) and inst or nil
  end
  local wq = {}   -- 给 WtDamage 查弹的：{ ammo 弹种键, id 武器号, kind }（同服务器那份武器表认弹的办法）
  local function penColor(st, I)
    local dir = I.p - I.o
    if dir.Magnitude < 1 then return nil end
    local ex = { st.em }
    if me.Character then table.insert(ex, me.Character) end
    if G.viewFolder then table.insert(ex, G.viewFolder) end
    rayP.FilterDescendantsInstances = ex
    local res = workspace:Raycast(I.o, dir.Unit * (dir.Magnitude + 6), rayP)
    local em = res and entOf(res.Instance)
    if not em or em:GetAttribute("Wreck") or (em:GetAttribute("Hp") or 1) <= 0 then return nil end
    local tm = em:GetAttribute("Team")
    if tm == nil or tm == me:GetAttribute("Side") then return nil end
    local d = em:GetAttribute("WtC") and VD.get(em:GetAttribute("Model") or "")
    local root = em:FindFirstChild("Root")
    if not d or not root then return nil end
    local base = root.CFrame * CF(0, -d.H / 2, 0)
    local p = base:PointToObjectSpace(res.Position)
    local dv = base:VectorToObjectSpace(dir.Unit)
    local yaw = em:GetAttribute("Ty") or 0
    wq.ammo, wq.id, wq.kind = I.am or (BAL.GUN[I.wid or ""] or {})[1], I.wid, I.w and I.w.kind   -- 还没换过弹种：这门炮的默认弹
    local pen, a = W.pen(wq, (res.Position - I.o).Magnitude / W.M)
    -- 打在还没炸的爆反块上（用户 11-27 挑刺：客户端穿深没算爆反，T-72B3、T-90M 会把破甲弹显示成能打穿）：按这辆车的爆反种类打折，同服务器 Era.lua G.eraShell
    local v = G.views and G.views[em]
    local era = v and v.M and v.M.era
    if era then
      local onBlock = false
      for _, blk in ipairs(era) do
        if not blk.blown then
          for _, q in ipairs(blk.parts or {}) do if q == res.Instance then onBlock = true break end end
        end
        if onBlock then break end
      end
      if onBlock then
        local L = TM.eraOf(d.id)
        local kind = (L and TM.ERA[L.kind]) or TM.ERA.fy2
        local amA = BAL.AMMO[wq.ammo or ""]
        local mult = (amA and amA.ce) and kind.k or kind.ke
        if mult and mult < 1 then pen = pen * ((a.t == "ce" and a.tandem) and math.max(mult, 0.85) or mult) end
      end
    end
    local zone, face, weak, n, _, dq = W.where(d, p, dv, yaw)
    local ang = math.deg(math.acos(math.clamp(-dq:Dot(n), -1, 1)))
    local eff = W.effective(W.armor(d, zone, face, a.t) * weak, ang, a.t)
    local rp = W.ricochet(a.t, ang)
    if pen < eff * 0.92 or rp >= 0.6 then return PEN_NO end
    if pen >= eff * 1.12 and rp < 0.15 then return PEN_OK end
    return PEN_MAYBE
  end

  ---------------------------------------------------------------- 底部正中：弹药栏
  -- 用户 11-27「目前这镜子底下的弹药切换没有设计感 很卡通」：原来是竖着的、几种颜色色块拼的弹 + 粗白框 + 琥珀大字从下往上涂——
  --   改成：单色、横放的弹种剪影（尾翼稳定脱壳穿甲弹细长杆 + 弹托 + 尾翼、破甲弹炸高探针、杀爆弹卵形头……），工具是细线图标；
  --   深色半透明的格子带竖向淡渐变、一像素细边；选中那格抬起一点、琥珀描边（docs/style.md：选中用琥珀描边）、底下一道琥珀线；
  --   装填是格子底部一道细线从左往右走 + 剩几秒（等宽小字），不再整格涂色；键位小方块、发数、弹种缩写全用等宽 / 窄体小字；
  --   弹种和工具中间一道细分隔线；上方写这一发的全名（3BM42 Mango · APFSDS）。颜色只表意（docs/style.md）：白灰打底，琥珀 = 选中 / 装填中，红 = 打空 / 起火
  local SW, SH, GAP, SEP = 62, 58, 4, 14
  local ICON, ICON_DIM = TH.C.TEXT, 0.5
  local BAR = frame(gui, UD2(0, 0, 0, SH + 30), UD2(0.5, 0, 1, -12), WHITE, 1, V2(0.5, 1))
  BAR.Name = "WtAmmoBar"
  local barScale = Instance.new("UIScale")
  barScale.Parent = BAR
  -- 整排后面一块很淡的底板（两头渐隐），把一格格连成一组
  local plate = frame(BAR, UD2(1, 40, 0, SH + 12), UD2(0.5, 0, 1, 4), TH.C.PANEL, 0.62, V2(0.5, 1))
  plate.Name = "Plate"
  do
    local g = Instance.new("UIGradient")
    g.Transparency = NumberSequence.new({ nk(0, 1), nk(0.12, 0), nk(0.88, 0), nk(1, 1) })
    g.Parent = plate
  end
  local divider = frame(BAR, UD2(0, 1, 0, SH - 22), UD2(0, 0, 1, -11), WHITE, 0.78, V2(0.5, 1))
  divider.Name = "Divider"
  -- 这一发的全名（弹药栏上方）
  local ammoName = label(BAR, "", UD2(1, 0, 0, 16), UD2(0.5, 0, 0, 0), 13, TH.C.TEXT, (TH.F and TH.F.cond) or MED, V2(0.5, 0))
  ammoName.Name = "AmmoName"
  local slots = {}
  -- 图标：单色剪影，横着放、弹头朝右，画在格子正中 46 × 18 的一块里；b(x, y, w, h, 透明, 圆角, 转角) 以这块的中心为原点
  local function icon(box, kind)
    box:ClearAllChildren()
    local function b(x, y, w, h, tr, r, rot)
      local f = frame(box, UD2(0, w, 0, h), UD2(0.5, x, 0.5, y), ICON, tr or 0, V2(0.5, 0.5))
      if r then round(f, (r == true) and UDim.new(0.5, 0) or UDim.new(0, r)) end
      if rot then f.Rotation = rot end
      return f
    end
    local function ring(x, y, dd, th)   -- 空心圆（细线）
      local f = round(frame(box, UD2(0, dd, 0, dd), UD2(0.5, x, 0.5, y), ICON, 1, V2(0.5, 0.5)))
      stroke(f, ICON, th or 1.5, 0)
      return f
    end
    local function dark(x, y, w, h)   -- 剪影上挖一道（弹带、钨珠）：底板色
      local f = frame(box, UD2(0, w, 0, h), UD2(0.5, x, 0.5, y), TH.C.PANEL, 0.1, V2(0.5, 0.5))
      f.ZIndex = 2
      return f
    end
    if kind == "ap" then   -- 尾翼稳定脱壳穿甲弹：细长杆、三瓣弹托、尾翼
      b(1, 0, 32, 2)
      b(17.5, 0, 3, 3, nil, nil, 45)
      b(-3, 0, 10, 7, 0.35, 1)
      b(-14, -2.6, 6, 1.6, nil, nil, -32)
      b(-14, 2.6, 6, 1.6, nil, nil, 32)
      b(-16.5, 0, 1.6, 7)
    elseif kind == "heat" or kind == "mpat" or kind == "jet" then   -- 破甲 / 多用途 / 射流：弹体、圆头、炸高探针、尾翼
      b(-3, 0, 16, 7, nil, 1)
      b(6.5, 0, 7, 6, nil, 3)
      b(13.5, 0, 8, 1.6)
      b(18, 0, 3, 3, nil, true)
      b(-13.5, 0, 3, 10, 0.25, 1)
      if kind == "mpat" then b(13, 0, 2, 4) end      -- 多用途：探针上的近炸环
      if kind == "jet" then dark(-1, 0, 1.5, 7) end  -- 串联：前后两级装药中间一道
    elseif kind == "he" then   -- 杀爆弹：弹体、卵形头、引信、弹带
      b(-3, 0, 20, 8, nil, 2)
      b(8.5, 0, 9, 6.5, nil, 3.2)
      b(14, 0, 3.5, 3, nil, 1)
      dark(-8, 0, 2, 8)
    elseif kind == "can" then   -- 霰弹：平头圆筒、一排钨珠
      b(0, 0, 24, 9, nil, 1)
      for k2 = -1, 1 do dark(k2 * 6 + 3, 0, 2.5, 2.5) end
    elseif kind == "sam" then   -- 导弹：弹体、头、前后两组翼
      b(0, 0, 28, 3, nil, 1.5)
      b(15, 0, 4, 4, nil, true)
      b(7, 0, 2, 8, 0.2)
      b(-11, 0, 3, 10, 0.2)
    elseif kind == "ac" then   -- 机炮弹：两发
      for _, y in ipairs({ -3.5, 3.5 }) do
        b(-4, y, 13, 4.5, nil, 1)
        b(5.5, y, 7, 3.8, nil, 1.9)
      end
    elseif kind == "mg" then   -- 机枪弹：一排三发
      for _, y in ipairs({ -5, 0, 5 }) do
        b(-3, y, 11, 2.8, nil, 1)
        b(4.5, y, 5, 2.6, nil, 1.3)
      end
    elseif kind == "smoke" then   -- 烟幕弹：发射筒 + 三团烟（淡）
      b(-7, 0, 11, 9, nil, 1)
      b(-1, 0, 2, 7)
      b(5, -2, 8, 8, 0.45, true)
      b(10, 1.5, 7, 7, 0.58, true)
      b(4.5, 3.5, 6, 6, 0.66, true)
    elseif kind == "scout" or kind == "bino" then   -- 侦察、车长望远镜：望远镜（两个细线圆 + 中间连接）
      ring(-6, 1, 11)
      ring(6, 1, 11)
      b(0, -1, 4, 3)
      b(-6, -6, 5, 3, 0.3, 1)
      b(6, -6, 5, 3, 0.3, 1)
    elseif kind == "arty" then   -- 火炮支援：瞄准圈 + 十字 + 往下落的炮弹
      ring(-3, 1, 14)
      b(-3, 1, 1.2, 18, 0.3)
      b(-3, 1, 18, 1.2, 0.3)
      b(9, -5, 3.5, 8, nil, 1.5, 25)
    elseif kind == "ext" then   -- 灭火器
      b(-2, 1, 16, 7, nil, 2)
      b(7.5, -2.5, 6, 2)
      b(4, -5, 4, 2)
    else   -- 维修：扳手（斜着的柄 + 开口的头）
      b(-2, 2, 22, 3, nil, 1.5, -35)
      local hd = ring(8, -6, 8, 2.2)
      hd.Rotation = -35
      dark(10.5, -8.5, 3.5, 3.5)
    end
  end
  local function newSlot(i)
    local s = {}
    s.f = round(frame(BAR, UD2(0, SW, 0, SH), UD2(0, 0, 1, 0), TH.C.PANEL, 0.45, V2(0, 1)), UDim.new(0, TH.R or 2))
    s.f.Name = "Slot" .. i
    s.f.ClipsDescendants = true
    TH.grad(s.f, Color3.fromRGB(70, 76, 80), Color3.fromRGB(12, 14, 16))   -- 竖向淡渐变：上面亮一点
    s.st = stroke(s.f, WHITE, 1, 0.84)
    s.ic = frame(s.f, UD2(0, 46, 0, 18), UD2(0.5, 0, 0.5, 1), WHITE, 1, V2(0.5, 0.5))
    s.ic.Name = "Icon"
    s.keyBox = round(frame(s.f, UD2(0, 13, 0, 13), UD2(0, 4, 0, 4), WHITE, 1), UDim.new(0, 2))
    s.keyS = stroke(s.keyBox, TH.C.MUTE, 1, 0.45)
    s.key = label(s.keyBox, "", UD2(1, 0, 1, 0), nil, 10, TH.C.MUTE, MONO_F)
    s.n = label(s.f, "", UD2(0, 36, 0, 14), UD2(1, -5, 0, 3), 13, WHITE, MONO_F, V2(1, 0), RIGHT)
    s.tag = label(s.f, "", UD2(1, -6, 0, 12), UD2(0.5, 0, 1, -8), 10, TH.C.MUTE, (TH.F and TH.F.cond) or MED, V2(0.5, 1))
    s.tag.Name = "Tag"
    s.track = frame(s.f, UD2(1, -10, 0, 2), UD2(0, 5, 1, -4), WHITE, 0.88, V2(0, 1))   -- 底部的细轨道
    s.prog = frame(s.track, UD2(0, 0, 1, 0), nil, TH.C.WARN, 0)                        -- 装填 / 冷却走到哪
    s.kind = nil
    s.x = 0
    slots[i] = s
    return s
  end

  -- 这辆车的弹药栏：主炮每种弹一格，别的武器一格，再加烟幕弹、维修 / 灭火
  local slotDef, slotKey = {}, nil
  local function buildSlots(d)
    local key = d.id .. ":" .. table.concat(d.weapons or {}, ",")
    if slotKey == key then return slotDef end
    slotKey = key
    slotDef = {}
    for wi, wid in ipairs(d.weapons or {}) do
      local w = VD.W[wid]
      local list = BAL.GUN[wid]
      if list then
        for _, k in ipairs(list) do
          local a = BAL.AMMO[k]
          local cls = a and a.cls or "ap"
          table.insert(slotDef, { k = "am", wi = wi, wid = wid, am = k, icon = (cls == "atgm") and "sam" or cls, tag = ({ ap = "APFSDS", heat = "HEAT", mpat = "MPAT", can = "CAN", he = "HE", jet = "射流", atgm = "ATGM" })[cls] or "" })
        end
      elseif w then
        local ic = (w.kind == "gun") and "mg" or ((w.kind == "sam" or w.kind == "atgm") and "sam" or ((w.kind == "arty" or (w.dmg or 0) >= 300) and "he" or "ac"))
        local tg = (w.kind == "atgm") and "ATGM" or ({ mg = "MG", sam = "SAM", he = "HE", ac = "AC" })[ic]
        table.insert(slotDef, { k = "w", wi = wi, wid = wid, icon = ic, tag = tg })
      end
    end
    local n = #slotDef
    for i, sd in ipairs(slotDef) do sd.num = (i <= 6) and i or nil end
    table.insert(slotDef, { k = "smoke", icon = "smoke", keyTxt = "M" })   -- 11-25 起烟幕是 M（X 是按住透视自己的车）
    table.insert(slotDef, { k = "fix", icon = "fix", keyTxt = "Y" })
    table.insert(slotDef, { k = "bino", icon = "bino", keyTxt = "C" })   -- 车长望远镜（用户 11-27，Drive / GunSight）
    if d.cat == "apc" or d.cat == "aa" then table.insert(slotDef, { k = "scout", icon = "scout", keyTxt = "G" }) end   -- 轻型车才能侦察（战雷）
    if d.cat ~= "aa" then table.insert(slotDef, { k = "arty", icon = "arty", keyTxt = "K" }) end   -- 防空车不能叫火炮
    for i = #slots + 1, #slotDef do newSlot(i) end
    for i, s in ipairs(slots) do
      local sd = slotDef[i]
      s.f.Visible = sd ~= nil
      if sd then
        s.kind = nil
        s.key.Text = sd.num and tostring(sd.num) or (sd.keyTxt or "")
        s.tag.Text = sd.tag or ""
        -- 武器和工具（烟幕 / 维修 / 望远镜……）中间空一截、一道细分隔线
        local x = (i - 1) * (SW + GAP) + ((i > n) and SEP or 0)
        s.x = x
        s.f.Position = UD2(0, x, 1, 0)
      end
    end
    BAR.Size = UD2(0, #slotDef * (SW + GAP) - GAP + SEP, 0, SH + 30)
    divider.Position = UD2(0, n * (SW + GAP) - GAP / 2 + SEP / 2, 1, -11)
    divider.Visible = n > 0 and #slotDef > n
    return slotDef
  end

  -- 数字键：照底部弹药栏一格一个数（主炮的弹种在前，战雷那样 1 穿甲 / 2 破甲……）；Drive.lua 先问这里
  local usedSt = nil   -- 这一趟开的车画过战雷界面（电脑布局）：开着瞄准镜时数字键也照这个排
  G.wtKeySlot = function(st, i)
    if not (st and st.d and st == usedSt) then return false end
    local sd = buildSlots(st.d)[i]
    if not sd or sd.num ~= i then return false end
    st.wi = sd.wi
    if sd.k == "am" and G.driveAmmo then G.driveAmmo(sd.am) end   -- 换弹种：Drive 的 cycleAmmo（换了要重新装一发）
    return true
  end

  local function stepBar(st, I)
    local d = st.d
    local def = buildSlots(d)
    local vs = G.S and G.S.veh
    local f = st.fcs
    local em = st.em
    local fire = em and em:GetAttribute("WtF") == true
    local fix = em and em:GetAttribute("WtFix")
    local t = os.clock()
    local curName = ""
    for i, sd in ipairs(def) do
      local s = slots[i]
      local sel, empty, cnt = false, false, ""
      local ic = sd.icon
      local fillK, timeTxt = nil, ""
      if sd.k == "am" or sd.k == "w" then
        local am = vs and vs.ammo and vs.ammo[sd.wid]
        local tot = am and (am[1] + am[2]) or nil
        -- ④ 配弹：每种弹各剩几发（服务器 Wt.lua 写 AmL = "m829a3:20,m830:12,…"）
        if sd.k == "am" and em then
          local L = em:GetAttribute("AmL")
          local n = L and string.match("," .. L .. ",", "," .. sd.am .. ":(%d+),")
          if n then tot = tonumber(n) end
        end
        cnt = tot and tostring(tot) or "∞"
        empty = tot == 0
        if sd.k == "am" then
          local c0 = (f and f.am) or (BAL.GUN[sd.wid] and BAL.GUN[sd.wid][1])
          sel = st.wi == sd.wi and c0 == sd.am
          if sel then
            local a = BAL.AMMO[sd.am]
            curName = (a and a.name or sd.am) .. ((sd.tag and sd.tag ~= "") and ("  ·  " .. sd.tag) or "")
          end
        else
          sel = st.wi == sd.wi
          if sel then curName = T("vw." .. sd.wid) end
        end
        if sel and I then
          if I.ready == false then fillK, timeTxt = I.relK, string.format("%.1fs", I.left or 0) else fillK = 1 end
        end
      elseif sd.k == "smoke" then
        local n = vs and vs.smoke or 0
        cnt, empty = tostring(n), n <= 0
      elseif sd.k == "arty" then   -- 火炮支援：冷却（服务器时间）；侦察助攻多给的次数写在右上
        local cd = me:GetAttribute("WtArtyCd")
        local left = cd and (cd - workspace:GetServerTimeNow()) or 0
        local bonus = me:GetAttribute("WtArtyBonus")
        if left > 0 and not bonus then fillK, timeTxt = 1 - left / 120, string.format("%ds", math.ceil(left)) end
        cnt = bonus and ("+" .. bonus) or ""
      elseif sd.k == "scout" then
        cnt = ""
      elseif sd.k == "bino" then   -- 望远镜开着：这格亮
        cnt = ""
        sel = st.binoc == true
      else
        if fire then ic = "ext" end
        if fix then fillK = fix end
        cnt = ""
      end
      if s.kind ~= ic then
        s.kind = ic
        icon(s.ic, ic)
      end
      -- 选中：抬起 4 像素、底子亮一点、琥珀描边；没选中：压暗；打空：更暗、发数红
      s.f.Position = UD2(0, s.x, 1, sel and -4 or 0)
      s.f.BackgroundTransparency = sel and 0.22 or (empty and 0.62 or 0.45)
      s.st.Color = sel and TH.C.WARN or WHITE
      s.st.Thickness, s.st.Transparency = sel and 1.5 or 1, sel and 0.1 or 0.84
      local icTr = empty and 0.78 or (sel and 0 or ICON_DIM)
      for _, q in ipairs(s.ic:GetDescendants()) do
        if q:IsA("Frame") and q.BackgroundColor3 == ICON then
          q:SetAttribute("Base", q:GetAttribute("Base") or q.BackgroundTransparency)
          q.BackgroundTransparency = 1 - (1 - q:GetAttribute("Base")) * (1 - icTr)
        elseif q:IsA("UIStroke") then
          q.Transparency = icTr
        end
      end
      s.n.Text = cnt
      s.n.TextColor3 = empty and PEN_NO or (sel and TH.C.TEXT or TH.C.MUTE)
      s.key.TextColor3 = sel and TH.C.TEXT or TH.C.MUTE
      s.keyS.Color = sel and TH.C.TEXT or TH.C.MUTE
      -- 装填 / 冷却：底部细线走到哪；剩几秒写在弹种缩写那一行（琥珀）
      if timeTxt ~= "" then
        s.tag.Text, s.tag.TextColor3 = timeTxt, TH.C.WARN
      else
        s.tag.Text, s.tag.TextColor3 = sd.tag or "", sel and TH.C.TEXT or TH.C.MUTE
      end
      s.track.Visible = fillK ~= nil
      if fillK then
        s.prog.Size = UD2(math.clamp(fillK, 0, 1), 0, 1, 0)
        s.prog.BackgroundColor3 = TH.C.WARN
        s.prog.BackgroundTransparency = (fillK >= 1) and 0.15 or 0
      end
      -- 起火：灭火那格一闪一闪（红）
      if sd.k == "fix" and fire then
        s.st.Color = ((t * 4) % 1 < 0.5) and PEN_NO or WHITE
        s.st.Transparency = 0
      end
    end
    ammoName.Text = curName
  end

  ---------------------------------------------------------------- 左下：损伤示意图
  local DI = frame(gui, UD2(0, 250, 0, 160), UD2(0, 252, 1, -14), WHITE, 1, V2(0, 1))
  DI.Name = "WtDamageInd"
  local diScale = Instance.new("UIScale")
  diScale.Parent = DI
  do   -- 很淡的黑底，左浓右淡
    local bg = frame(DI, UD2(1, 0, 1, 0), nil, INK, 0.55)
    round(bg, UDim.new(0, 4))
    local g = Instance.new("UIGradient")
    g.Transparency = NumberSequence.new({ nk(0, 0.1), nk(0.6, 0.35), nk(1, 1) })
    g.Parent = bg
  end
  local SCW, SCH = 112, 150
  local sch = frame(DI, UD2(0, SCW, 0, SCH), UD2(0, 4, 0, 5), WHITE, 1)
  sch.Name = "Schematic"
  local diName = label(DI, "", UD2(0, 130, 0, 14), UD2(0, SCW + 10, 0, 8), 12, RGB(214, 220, 222), MED, nil, LEFT)
  diName.TextTruncate = Enum.TextTruncate.AtEnd
  local diSpd = label(DI, "0", UD2(0, 64, 0, 32), UD2(0, SCW + 10, 0, 26), 30, WHITE, BOLD, nil, LEFT)
  label(DI, "km/h", UD2(0, 40, 0, 12), UD2(0, SCW + 11, 0, 58), 11, RGB(190, 196, 198), MED, nil, LEFT)
  local gearBox = round(frame(DI, UD2(0, 28, 0, 28), UD2(0, SCW + 84, 0, 30), INK, 0.45), UDim.new(0, 3))
  stroke(gearBox, WHITE, 1, 0.55)
  local diGear = label(gearBox, "N", UD2(1, 0, 1, 0), nil, 17, WHITE, BOLD)
  local diTip = label(DI, "", UD2(0, 130, 0, 34), UD2(0, SCW + 10, 0, 80), 12, WHITE, BOLD, nil, LEFT)
  diTip.TextWrapped = true
  diTip.TextYAlignment = Enum.TextYAlignment.Top
  local fixBg = frame(DI, UD2(0, 122, 0, 3), UD2(0, SCW + 10, 0, 122), WHITE, 0.82)
  local fixFill = frame(fixBg, UD2(0, 0, 1, 0), nil, AMBER, 0)
  local diCrew = label(DI, "", UD2(0, 130, 0, 14), UD2(0, SCW + 10, 0, 134), 11, RGB(190, 196, 198), MED, nil, LEFT)

  local SC = { d = nil }
  -- 一个小人（头 + 身子）：乘员
  local function person(parent)
    local o = { f = frame(parent, UD2(0, 12, 0, 13), nil, WHITE, 1, V2(0.5, 0.5)) }
    o.f.ZIndex = 5
    o.head = round(frame(o.f, UD2(0, 5, 0, 5), UD2(0.5, 0, 0, 0), C_OK, 0, V2(0.5, 0)))
    o.body = round(frame(o.f, UD2(0, 10, 0, 7), UD2(0.5, 0, 1, 0), C_OK, 0, V2(0.5, 1)), UDim.new(0, 3))
    o.hs, o.bs = stroke(o.head, INK, 1, 0.35), stroke(o.body, INK, 1, 0.35)
    o.head.ZIndex, o.body.ZIndex = 5, 5
    o.x = label(o.f, "×", UD2(1, 4, 1, 4), UD2(0.5, 0, 0.5, 0), 15, PEN_NO, BOLD, V2(0.5, 0.5))
    o.x.ZIndex = 6
    o.x.Visible = false
    return o
  end
  local function buildSch(d)
    sch:ClearAllChildren()
    SC = { d = d, mods = {}, crew = {}, lay = W.layout(d) }
    local lay = SC.lay
    local L, Wd = d.L, d.W
    local k = math.min((SCH - 18) / L, (SCW - 34) / Wd)
    local cx, cy = SCW / 2, SCH / 2 + 4
    SC.k, SC.cx, SC.cy = k, cx, cy
    local function hullPx(x, z) return cx + x * k, cy + z * k end
    -- 车体轮廓（车头朝上），车头一道短横线
    local hb = round(frame(sch, UD2(0, Wd * k, 0, L * k), UD2(0, cx, 0, cy), RGB(30, 34, 36), 0.6, V2(0.5, 0.5)), UDim.new(0, 3))
    stroke(hb, WHITE, 1.2, 0.35)
    frame(sch, UD2(0, Wd * k * 0.4, 0, 2), UD2(0, cx, 0, cy - L * k / 2 - 3), WHITE, 0.35, V2(0.5, 1))
    -- 炮塔：一个转的框（绕座圈中心转），里面炮塔轮廓、炮管、炮闩……
    local tp = lay.tp
    local R = math.max(L, Wd) * k * 1.2
    local tg = nil
    if d.turret then
      local px, py = hullPx(tp.X, tp.Z)
      tg = frame(sch, UD2(0, R * 2, 0, R * 2), UD2(0, px, 0, py), WHITE, 1, V2(0.5, 0.5))
      tg.Name = "Turret"
      tg.ZIndex = 3
      local ts = lay.ts
      local tb = round(frame(tg, UD2(0, ts.X * k, 0, ts.Z * k), UD2(0.5, 0, 0.5, 0), RGB(36, 40, 42), 0.35, V2(0.5, 0.5)), UDim.new(0, 5))
      tb.ZIndex = 3
      stroke(tb, WHITE, 1.2, 0.25)
    end
    SC.tg, SC.R = tg, R
    for _, it in ipairs(lay.list) do
      local c = (it.lo + it.hi) / 2
      local sz = it.hi - it.lo
      if it.kind == "crew" then
        local o = person(sch)
        o.it, o.tur, o.cx, o.cz = it, it.tur, c.X, c.Z
        table.insert(SC.crew, o)
      else
        local parent = (it.tur and tg) or sch
        local f
        if it.tur and tg then
          f = frame(tg, UD2(0, math.max(2, sz.X * k), 0, math.max(2, sz.Z * k)), UD2(0.5, c.X * k, 0.5, c.Z * k), M_OK, 0.8, V2(0.5, 0.5))
        else
          local px, py = hullPx(c.X, c.Z)
          f = frame(parent, UD2(0, math.max(2, sz.X * k), 0, math.max(2, sz.Z * k)), UD2(0, px, 0, py), M_OK, 0.8, V2(0.5, 0.5))
        end
        round(f, UDim.new(0, (it.k == "barrel") and 1 or 2))
        f.ZIndex = it.tur and 4 or 2
        f.Name = it.k
        local s = stroke(f, M_OK, 1, 0.55)
        table.insert(SC.mods, { it = it, f = f, s = s, last = 2, flash = 0 })
      end
    end
    -- 起火：一团火（发动机那里）
    SC.fire = round(frame(sch, UD2(0, 16, 0, 16), UD2(0, cx, 0, cy), RGB(255, 120, 30), 0.15, V2(0.5, 0.5)))
    SC.fire.ZIndex = 7
    SC.fire.Visible = false
    for _, m in ipairs(SC.mods) do
      if m.it.k == "engine" then
        local c = (m.it.lo + m.it.hi) / 2
        SC.fire.Position = UD2(0, cx + c.X * k, 0, cy + c.Z * k)
      end
    end
  end

  local function stepDI(st)
    local d = st.d
    local em = st.em
    if not d then DI.Visible = false return end
    DI.Visible = true
    if SC.d ~= d then buildSch(d) end
    local t = os.clock()
    local yaw = st.ty or (em and em:GetAttribute("Ty")) or 0
    if SC.tg then SC.tg.Rotation = yaw end
    -- 乘员：按座位（谁坐在这个位子上、活没活；换了位子的跟着人走）
    local wc = em and em:GetAttribute("WtC") or ""
    local seat, have, alive, tot = {}, {}, 0, 0
    for tok in string.gmatch(wc, "[^,]+") do
      local s, sn = tonumber(string.sub(tok, 1, 1)) or 2, string.sub(tok, 2)
      tot += 1
      if s > 0 then alive += 1 end
      if seat[sn] == nil or s > seat[sn] then seat[sn] = s end
      have[sn] = true
    end
    local a = math.rad(yaw)
    local ca, sa = math.cos(a), math.sin(a)
    local tp = SC.lay.tp
    for _, o in ipairs(SC.crew) do
      local x, z = o.cx, o.cz
      if o.tur then x, z = tp.X + o.cx * ca - o.cz * sa, tp.Z + o.cx * sa + o.cz * ca end   -- 炮塔里的人跟着炮塔转（小人本身不转，免得倒过来）
      o.f.Position = UD2(0, SC.cx + x * SC.k, 0, SC.cy + z * SC.k)
      local s = have[o.it.role] and seat[o.it.role] or 0
      local col = (s == 2) and C_OK or ((s == 1) and C_HURT or C_DEAD)
      o.head.BackgroundColor3, o.body.BackgroundColor3 = col, col
      o.x.Visible = s == 0
    end
    -- 模块
    local wm = em and em:GetAttribute("WtM") or ""
    for i, m in ipairs(SC.mods) do
      local s = tonumber(string.sub(wm, i, i)) or 2
      if s < m.last then m.flash = t + 1.2 end
      m.last = s
      local col, tr = M_OK, 0.8
      if s == 1 then col, tr = M_HURT, 0.2 elseif s == 0 then col, tr = M_DEAD, 0.1 end
      if t < m.flash and (t * 8) % 1 < 0.5 then col, tr = WHITE, 0 end
      m.f.BackgroundColor3, m.f.BackgroundTransparency = col, tr
      m.s.Color, m.s.Transparency = col, (s == 2) and 0.55 or 0
    end
    local fire = em and em:GetAttribute("WtF") == true
    SC.fire.Visible = fire
    if fire then
      local pu = 0.5 + 0.5 * math.sin(t * 9)
      SC.fire.Size = UD2(0, 13 + 6 * pu, 0, 13 + 6 * pu)
      SC.fire.BackgroundColor3 = RGB(255, 90 + math.floor(90 * pu), 30)
    end
    -- 右边：车名、车速、档位、提示
    diName.Text = string.match(T("veh." .. d.id), "^(%S+)") or d.id
    diSpd.Text = tostring(math.floor(math.abs(st.speed or 0) / 2.8 * 3.6 + 0.5))
    local back = (st.speed or 0) < -0.4
    local gn = st.gearN or 0
    diGear.Text = st.locked and "-" or ((gn >= 1) and tostring(gn) or ((gn <= -1 or back) and ((st.gb and st.gb.nr > 1 and gn <= -1) and ("R" .. tostring(-gn)) or "R") or "N"))   -- 倒挡两档：R1 / R2
    diGear.TextColor3 = back and AMBER or WHITE
    local fix = em and em:GetAttribute("WtFix")
    local anyBad = false
    for _, m in ipairs(SC.mods) do if m.last < 2 then anyBad = true break end end
    if em and em:GetAttribute("WtMob") == false then anyBad = true end
    if fire then diTip.Text, diTip.TextColor3 = T("wt.tipFire"), ((t * 3) % 1 < 0.6) and PEN_NO or AMBER
    elseif fix then diTip.Text, diTip.TextColor3 = T("wt.tipFixing", math.floor(fix * 100)), AMBER
    elseif anyBad then diTip.Text, diTip.TextColor3 = T("wt.tipFix"), WHITE
    else diTip.Text = "" end
    fixBg.Visible = fix ~= nil
    fixFill.Size = UD2(math.clamp(fix or 0, 0, 1), 0, 1, 0)
    diCrew.Text = (tot > 0) and T("wtt.crew", alive, tot) or ""
    -- ④ 待发弹架：还剩几发（空了写红字「车体取弹」——装得慢）
    local rdy, rcap = em and em:GetAttribute("Rdy"), em and em:GetAttribute("RdyCap")
    if rdy and rcap then
      diCrew.Text = diCrew.Text .. "   " .. ((rdy > 0) and T("wtt.rack", rdy, rcap) or T("wtt.rackOut"))
    end
  end

  ---------------------------------------------------------------- 每帧（VehHud.stepTank 调）
  local shownT, lastVp = -9, nil
  local function layout()
    local vp = cam.ViewportSize
    if vp == lastVp then return end
    lastVp = vp
    local s = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.8, 1.25)
    barScale.Scale, diScale.Scale = s, s
  end
  -- I：{ p 炮指的点、o 炮口、relK / ready / left 装填、wid / w 选中的武器、am 弹种 }；没有炮（车上只有机枪的）I.p 是 nil：只画弹药栏、损伤图
  function G.wtTankStep(st, I)
    shownT = os.clock()
    usedSt = st
    gui.Enabled = true
    layout()
    local t = os.clock()
    if I and I.p then
      local sp, on = cam:WorldToViewportPoint(I.p)
      AIM.root.Visible = on
      AIM.root.Position = UD2(0, sp.X, 0, sp.Y)
      local col = WHITE
      AIM.block.Visible = on and I.blocked == true
      if I.blocked then
        col = PEN_NO   -- 炮口被挡：不算穿深，圈红
      elseif on and I.w then
        local ok, c = pcall(penColor, st, I)
        if ok and c then col = c end
      end
      AIM.ringS.Color, AIM.dot.BackgroundColor3 = col, col
      for _, tk in ipairs(AIM.ticks) do tk.BackgroundColor3 = col end
      -- 装填：弧走着（琥珀），装好那一下圈涨一下
      local ready = I.ready ~= false
      if ready and not wasReady then
        readyT = t
        if G.wtVoice and wasReady == false then G.wtVoice("loaded") end   -- 车组语音：装填完毕（⑬）
      end
      wasReady = ready
      local flash = ready and (t - readyT) < 0.45   -- 刚装好：整圈绿亮一下
      AIM.rel.root.Visible = (not ready) or flash
      AIM.track.Transparency = (ready and not flash) and 1 or 0.7
      if not ready then AIM.rel.set(I.relK or 0, relColor(I.relK)) elseif flash then AIM.rel.set(1, PEN_OK) end
      AIM.relT.TextColor3 = relColor(I.relK)
      AIM.relT.Text = ready and "" or string.format("%.1f", I.left or 0)
      local pop = math.clamp(1 - (t - readyT) / 0.25, 0, 1)
      AIM.scale.Scale = 1 + 0.18 * pop
      -- 测距（用户 11-25「全部都做」⑤）：街机照旧一直写到瞄准点多远；历史 / 全真按 R 才有——有激光测距的马上准，
      --   没有的（豹 1、M60A1、BMP-1）车长估两秒、报个整 50 米的数（≈）；10 秒后作废
      local wm = workspace:GetAttribute("WtMode")
      if wm == "rb" or wm == "sb" then
        local f = st.fcs
        if f and f.estimating then AIM.rng.Text = T("wtt.est")
        elseif f and f.R and (f.man or (f.laseT and t - f.laseT < 10)) then AIM.rng.Text = (f.est and "≈" or "") .. T("vh.m", f.R)
        elseif f and f.noRet and f.laseT and t - f.laseT < 3 then AIM.rng.Text = "----"
        else AIM.rng.Text = T("wtt.rkey") end
      else
        AIM.rng.Text = T("vh.m", math.floor((I.p - I.o).Magnitude / 2.8 / 5 + 0.5) * 5)
      end
    else
      AIM.root.Visible = false
    end
    local ok, err = pcall(stepBar, st, I)
    if not ok and G.showError then G.showError("战雷弹药栏：" .. tostring(err)) end
    ok, err = pcall(stepDI, st)
    if not ok and G.showError then G.showError("战雷损伤图：" .. tostring(err)) end
  end
  G.wtTankShown = function() return gui.Enabled end   -- TankHud（车旁车速牌）、WtHud（旧的车组面板）看这个收起
  G.wtTankSlots = function() return slotDef end   -- 测试用

  G.frameConn("WtTank", function()
    if gui.Enabled and os.clock() - shownT > 0.15 then gui.Enabled = false end   -- 下车、开瞄准镜、换触屏布局：VehHud 不调了
  end)
end

return WtTank
