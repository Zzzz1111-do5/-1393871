-- Roblox全面大战场（客户端）——战雷式坦克界面（用户 11-24 夜「把整个游戏做成战雷」②：坦克战雷化）
--   电脑上开坦克时 VehHud 的 stepTank 每帧调 G.wtTankStep，原来 MWT 那套（右下全息车、六边形弹种钮、∧ 准星、车旁的车速牌）收起：
--   · 准星：炮现在指的地方一个圆（中心一点、左右下三道刻度），颜色就是战雷的穿深指示——照服务器 Wt.lua 同一套算
--     （WtDamage：瞄着的那一处几毫米、入射角换算的等效厚度、这种弹在这个距离的穿深、跳弹概率）：
--     绿 打得穿，黄 说不准（穿深和等效厚度差不多、或者可能跳弹），红 打不穿 / 会跳弹，没瞄着敌方车辆是白的；
--     圈外一道装填弧（顺时针走满就装好），左边剩几秒、右边测距
--   · 底部正中：弹药栏——主炮每种弹一格（数字键直接选，战雷那样）、机炮 / 机枪各一格，烟幕弹（M）、维修 / 灭火（Y）、望远镜（C）……；
--     每格一张写实弹种图（AmmoPics，Blender 按真弹渲的），选中琥珀描边 + 底边琥珀线，装填时底边进度条 + 剩几秒；打光了图去色、发数变红
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
  local BOLD, MED = Enum.Font.BuilderSansMedium, Enum.Font.BuilderSans
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
        -- 爆反型号：这辆车挂的（模型属性 Mods 的 era，同服务器 Era.lua G.eraSetup；11-27 起 96B 出厂也是 FY-4），没有才按模型自带的
        local mm = TM.decode(em:GetAttribute("Mods") or "")
        local kind = TM.ERA[mm.era or ""] or (L and TM.ERA[L.kind]) or TM.ERA.fy2
        local amA = BAL.AMMO[wq.ammo or ""]
        local mult
        if (I.w and I.w.kind == "atgm") or (amA and amA.cls == "atgm") then
          mult = W.singleCharge(wq) and kind.k or (kind.kt or kind.k)   -- 反坦克导弹、炮射导弹：单装药按 k、串联按 kt（同服务器 Era.lua G.eraBlast）
        else
          mult = (amA and amA.ce) and kind.k or kind.ke
        end
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
  -- 用户 11-27 晚：「我需要你完全按照战雷的风格去做设计 而不是这种卡通风格……更拟真」（嫌上一版的单色剪影还是卡通）——
  --   弹种图换成写实渲染图（ReplicatedStorage.AmmoPics，tools/models/ammopics_blender.py：Blender 按真弹的结构建模、照实物涂装，
  --   真材质：黄铜、钢、可燃药筒、黑弹托……）：横放、弹头朝右、弹尖压在格子右边 6 像素，药筒往左伸出格子、最后 16 像素 UIGradient 渐隐；
  --   同一门炮的弹一个毫米 → 像素比例（M1028 就是比 M829A3 短、榴弹就是比穿甲弹粗），整排像一张弹药识别图；
  --   机枪格是一小段弹链，工具格（烟幕弹、扳手 / 灭火器、望远镜、电台话筒、激光测距仪）也是实物渲染，同一套光。
  --   用不了 EditableImage（游戏设置没开 Mesh / Image API）时退回单色剪影（icon）。
  --   界面骨架零装饰：格子平涂深色半透明底 + 1 像素细线、小圆角，不要玻璃渐变、不抬起；
  --   三组：主炮弹 | 机枪 / 其他武器 | 工具，组间一道细竖线，不要整排的底板；
  --   字只用 Theme.S 的字号，战场字黑描边：右上发数（等宽 15）、左上 12 × 12 键位框（等宽 12 灰）、选中那格左下类型（窄体 12）、
  --   右下冷却秒数（等宽 12）；整排上方名牌写这一发的全称（窄体 15 白「M829A3」+ 13 灰「· APFSDS-T」），装填时右边「装填 4.1 s」。
  --   颜色只表示状态（白、灰、琥珀、红，不用蓝）：选中（下一发装这种）琥珀细描边；装好了键位框右边一个 4 像素白点；
  --   装填中底边一道琥珀进度条从左往右匀速走、图压暗到八成，装好 120 毫秒内图回来；
  --   打空：图去色、35% 不透明、发数红 0，按它的键描边红闪两下、名牌写「无弹」；冷却：暗遮罩从上往下退 + 灰色秒数；
  --   主炮坏了（炮长阵亡 / 炮闩炮管损毁）：图 25%、发数变暗、键位框变暗，名牌右边一次红字「主炮损坏」；补给：发数每加 1 白闪 80 毫秒。
  --   动效 80～150 毫秒（线性），不跳、不缩放、不抬升、不循环闪；整排出现时淡入 150 毫秒
  -- 11-27 美术审查（17 条）以后：
  --   · 状态信号去重：「选中」和「膛内」在这个游戏里永远是同一格（换弹种就重新装填）——左边白竖条、平时的底边琥珀线去掉，
  --     底边线只在装填 / 维修时当进度条；装填秒数只写在名牌右边（格子里不再重复）；装填压暗六成 → 八成（DTC10 不再成一团泥）
  --   · 格子不挤：没选中的格子不写类型（名牌上有），图区 34 → 40 高、从 y 10 起，键位框 14 → 12；
  --     名牌后面垫一条两端渐隐的暗底（亮地面上浅灰字看得清；描边照规范 0.45）
  --   · 去掉图后面那块横向柔光（上下是硬边的一条亮横带）：渲染里加了一盏下后方的轮廓光，黑件的上下沿都勾出来了
  --   · 带药筒的左边 16 像素「先压暗、后透明」：颜色在 16 像素内从 0.25 灰到白、透明度只在最左 4 像素里从 1 到 0（读起来是药筒伸进阴影，不是雾）
  --   · 图两套：屏幕（逻辑像素）高 ≥ 850 用 2 倍图（1080p：正好 2:1；Retina Mac 1470 × 956 这类：接近 1:1），更矮的用 1 倍
  --     （1280 × 720、1366 × 768 这类低分屏格子只有 78 像素宽，2 倍图要缩 2.4 倍，没有 mipmap 时细杆断线、字成噪点）——
  --     Roblox 不给脚本看屏幕的 DPI 缩放，只能按逻辑屏高估
  --   · 上车时按格子排队解图（HudArt G.ammoPicPump：每帧一张，彩色的先、去色的后），整排都解好了才一起显示；
  --     有一格解不出 / 没有图就整排退回剪影（不混着）；只有 EditableImage 建不出来才算用不了，换车再试一次
  --   · 每帧只在值变了的时候才写属性（put；名牌的字串也只在内容变了时才拼）——M3 上省下每格每帧二十来次属性写入
  -- 11-27 美术审查第二轮以后：
  --   · 主炮坏了只说一次：原来 5 个弹种格都把发数换成红字「损坏」（左下损伤图、「按 Y 维修」也在说）——格子里发数照写
  --     （FAINT、透明 0.4），图照样压到 25%、键位框变暗；只在名牌这一行右边（装填秒数的位置）写一次红色「主炮损坏」
  --   · 装填秒数只说一次：车外的准星在屏幕上时它自己写着秒数 + 琥珀弧，名牌右边就不写；开镜、望远镜里没有那个准星
  --     （瞄准镜里只有一个装好的小方块），名牌照写
  --   · 换分辨率不闪：窗口跨过逻辑高 850（Mac 在窗口和全屏之间切）时，旧的那套图先留着显示，新的一套在后台每帧解一张，
  --     全解好了一起换（原来整排先清掉、约 18 帧后才淡入回来）
  local AW, AH, TW = 96, 60, 60      -- 弹种 / 机枪格、工具格（按 1080p 的像素，整排再按屏幕高缩放，layout）
  local GAP, GRP = 4, 10             -- 格间距；组之间各空 10 像素、中间一道 1 像素的线
  local PLATE = 22                   -- 名牌那一行
  local IMG_Y, IMG_H = 10, 40        -- 图区：x 0～92（工具格 2～58）、y 10～50（弹轴压在 y 30）
  local KEY = 12                     -- 键位框
  local COND_F = (TH.F and TH.F.cond) or MED
  local SZ = TH.S or { tiny = 12, small = 13, body = 15 }
  local MUTE, FAINT = TH.C.MUTE, TH.C.FAINT
  local ICON = TH.C.TEXT
  local BAR = frame(gui, UD2(0, 0, 0, AH + PLATE), UD2(0.5, 0, 1, -16), WHITE, 1, V2(0.5, 1))
  BAR.Name = "WtAmmoBar"
  local barScale = Instance.new("UIScale")
  barScale.Parent = BAR
  local dividers = {}
  local function divider(k)
    local dv = dividers[k]
    if not dv then
      dv = frame(BAR, UD2(0, 1, 0, AH - 16), UD2(0, 0, 1, -8), WHITE, 0.85, V2(0.5, 1))
      dv.Name = "Divider"
      dividers[k] = dv
    end
    return dv
  end
  -- 只在值变了时才写（每帧每格二十来个属性，大多数帧里都没变）：c 是这个东西自己的「上次写的值」表
  local function put(c, key, obj, prop, v)
    if c[key] ~= v then
      c[key] = v
      obj[prop] = v
    end
  end
  -- 名牌：这一发的全称；右边装填剩几秒；后面垫一条两端渐隐的暗底（亮地面上也看得清）
  local plateBg = frame(BAR, UD2(0, 0, 0, 20), UD2(0, -8, 0, -1), TH.C.PANEL, 0.5)
  plateBg.Name = "PlateBg"
  do
    local g = Instance.new("UIGradient")
    g.Transparency = NumberSequence.new({ nk(0, 1), nk(0.08, 0), nk(0.92, 0), nk(1, 1) })
    g.Parent = plateBg
  end
  local ammoName = label(BAR, "", UD2(0, 420, 0, 18), UD2(0, 2, 0, 0), SZ.body, TH.C.TEXT, COND_F, V2(0, 0), LEFT)
  ammoName.Name = "AmmoName"
  ammoName.RichText = true
  ammoName.ZIndex = 2
  local loadTxt = label(BAR, "", UD2(0, 140, 0, 18), UD2(0, 0, 0, 0), SZ.small, AMBER, MONO_F, V2(1, 0), RIGHT)
  loadTxt.Name = "LoadTime"
  loadTxt.ZIndex = 2
  local plateC = {}   -- 名牌这一行上次写的值（put）
  local function hex(c) return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end
  local MUTE_HEX = hex(MUTE)
  -- 全称、类型（名牌）和左下的短类型；没写的弹按 Ballistics 的 name
  local AMMO_INFO = {
    m829a3 = { "M829A3", "APFSDS-T", "APFSDS" }, m830 = { "M830", "HEAT-MP-T", "HEAT-MP" }, m830a1 = { "M830A1", "MPAT", "MPAT" },
    m1028 = { "M1028", "Canister", "CAN" }, m900 = { "M900", "APFSDS-T", "APFSDS" }, m456 = { "M456A2", "HEAT-T", "HEAT" },
    m833 = { "M833", "APFSDS-T", "APFSDS" }, m392 = { "M392A2", "APDS-T", "APDS" }, m409 = { "M409", "HEAT-MP-T", "HEAT-MP" },
    dm53 = { "DM53", "APFSDS-T", "APFSDS" }, dm33 = { "DM33", "APFSDS-T", "APFSDS" }, dm12 = { "DM12", "HEAT-MP-T", "HEAT-MP" },
    dm13 = { "DM13", "APDS-T", "APDS" }, dm33l7 = { "DM33 (105)", "APFSDS-T", "APFSDS" }, dm12h = { "DM12 (105)", "HEAT-T", "HEAT" },
    dtc10 = { "DTC10-125", "APFSDS", "APFSDS" }, heat125 = { "125 HEAT-FS", "HEAT-FS", "HEAT-FS" }, he125 = { "125 HE-FRAG", "HE-FRAG", "HE-FRAG" },
    bm60 = { "3BM60 Svinets-2", "APFSDS", "APFSDS" }, bm42 = { "3BM42 Mango", "APFSDS", "APFSDS" }, bm22 = { "3BM22 Zakolka", "APFSDS", "APFSDS" },
    bm15 = { "3BM15", "APFSDS", "APFSDS" }, bk31 = { "3BK31", "HEAT-FS (tandem)", "HEAT-FS" }, bk18m = { "3BK18M", "HEAT-FS", "HEAT-FS" },
    of26 = { "3OF26", "HE-FRAG", "HE-FRAG" }, refleks = { "9M119M Refleks", "ATGM", "ATGM" },
    br412d = { "BR-412D", "APBC-T", "APBC" }, bk5m = { "BK-5M", "HEAT-FS", "HEAT-FS" }, of412 = { "OF-412", "HE-FRAG", "HE-FRAG" },
    apfsds69 = { "100mm APFSDS", "APFSDS", "APFSDS" },
  }
  local function ammoInfo(k)
    local a = BAL.AMMO[k]
    if a and a.cls == "jet" then   -- 游戏里的「金属射流弹」：按口径叫
      local cal = string.match(k, "%d+") or ""
      return T("wtt.jet", cal), T("wtt.jetType"), T("wtt.tagJet")
    end
    local i = AMMO_INFO[k]
    if i then return i[1], i[2], i[3] end
    return (a and a.name) or k, "", (a and a.sym) or ""
  end
  local slots = {}
  -- 后备图标（用不了 EditableImage 时）：单色剪影，横着放、弹头朝右，画在图片区正中 46 × 18 的一块里；b(x, y, w, h, 透明, 圆角, 转角) 以这块的中心为原点
  local function icon(box, kind)
    box:ClearAllChildren()
    local function b(x, y, w, h, tr, r, rot)
      local f = frame(box, UD2(0, w, 0, h), UD2(0.5, x, 0.5, y), ICON, tr or 0, V2(0.5, 0.5))
      f.ZIndex = 2
      if r then round(f, (r == true) and UDim.new(0.5, 0) or UDim.new(0, r)) end
      if rot then f.Rotation = rot end
      return f
    end
    local function ring(x, y, dd, th)   -- 空心圆（细线）
      local f = round(frame(box, UD2(0, dd, 0, dd), UD2(0.5, x, 0.5, y), ICON, 1, V2(0.5, 0.5)))
      f.ZIndex = 2
      stroke(f, ICON, th or 1.5, 0)
      return f
    end
    local function dark(x, y, w, h)   -- 剪影上挖一道（弹带、钨珠）：底板色
      local f = frame(box, UD2(0, w, 0, h), UD2(0.5, x, 0.5, y), TH.C.PANEL, 0.1, V2(0.5, 0.5))
      f.ZIndex = 3
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
    elseif kind == "arty" then   -- 火炮支援：野战电台话筒（同写实图：弯手柄、两头朝下的听筒 / 话筒、背上的按讲键；原来画的是准星，两套图意思不一样）
      b(0, -2.5, 24, 3.4, nil, 1.7)
      b(-12, 1.5, 7, 6.5, nil, 2, -14)
      b(12, 1.5, 6, 5.5, nil, 2, 14)
      b(0, -5.5, 8, 2, 0.3, 1)
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
    s.f = round(frame(BAR, UD2(0, AW, 0, AH), UD2(0, 0, 1, 0), TH.C.PANEL, 0.35, V2(0, 1)), UDim.new(0, TH.R or 2))
    s.f.Name = "Slot" .. i
    s.f.ClipsDescendants = true
    s.st = stroke(s.f, WHITE, 1, 0.85)
    -- （原来图后面一块 88 × 34 的横向柔光：上下是硬边的一条亮横带——去掉，黑件靠渲染里下后方那盏轮廓光勾边）
    s.img = Instance.new("ImageLabel")
    s.img.Name = "Pic"
    s.img.BackgroundTransparency = 1
    s.img.BorderSizePixel = 0
    s.img.Size, s.img.Position = UD2(0, 92, 0, IMG_H), UD2(0, 0, 0, IMG_Y)
    s.img.ZIndex = 2
    s.img.Visible = false
    s.img.Parent = s.f
    -- 药筒往左伸出格子：最左边 16 像素「先压暗、后透明」——颜色从 0.25 灰过到白（药筒伸进阴影里），
    --   透明度只在最左 4 像素里从 1 到 0（原来浅色药筒整段透明渐隐，读成一团往左淡出的白雾）；图不伸出去的（125 毫米分装弹、工具）关掉
    s.imgFade = Instance.new("UIGradient")
    do
      local e, f = 16 / 92, 4 / 92
      local g0 = Color3.new(0.25, 0.25, 0.25)
      s.imgFade.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, g0), ColorSequenceKeypoint.new(e * 0.5, g0:Lerp(WHITE, 0.62)),
        ColorSequenceKeypoint.new(e, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)) })
      s.imgFade.Transparency = NumberSequence.new({ nk(0, 1), nk(f * 0.5, 0.4), nk(f, 0), nk(1, 0) })
    end
    s.imgFade.Enabled = false
    s.imgFade.Parent = s.img
    s.ic = frame(s.f, UD2(0, 46, 0, 18), UD2(0, 46, 0, IMG_Y + IMG_H / 2), WHITE, 1, V2(0.5, 0.5))   -- 后备：单色剪影
    s.ic.Name = "Icon"
    s.mask = frame(s.f, UD2(1, 0, 0, 0), UD2(0, 0, 1, 0), TH.C.PANEL, 0.3, V2(0, 1))   -- 冷却：暗遮罩，从上往下退
    s.mask.Name = "Cooldown"
    s.mask.ZIndex = 3
    s.mask.Visible = false
    s.keyBox = frame(s.f, UD2(0, KEY, 0, KEY), UD2(0, 4, 0, 4), WHITE, 1)
    s.keyBox.ZIndex = 4
    s.keyS = stroke(s.keyBox, MUTE, 1, 0)
    s.key = label(s.keyBox, "", UD2(1, 0, 1, 0), nil, SZ.tiny, MUTE, MONO_F)
    s.key.ZIndex = 4
    s.rdy = round(frame(s.f, UD2(0, 4, 0, 4), UD2(0, 4 + KEY + 4, 0, 4 + KEY / 2), WHITE, 0, V2(0, 0.5)))   -- 装好了：键位框右边一个白点
    s.rdy.Name = "Ready"
    s.rdy.ZIndex = 4
    s.rdy.Visible = false
    s.nBg = frame(s.f, UD2(0, 28, 0, 16), UD2(1, -3, 0, 2), WHITE, 1, V2(1, 0))   -- 补给：发数后面白闪一下
    s.nBg.ZIndex = 4
    s.n = label(s.f, "", UD2(0, 46, 0, 16), UD2(1, -6, 0, 2), SZ.body, WHITE, MONO_F, V2(1, 0), RIGHT)
    s.n.ZIndex = 5
    s.tag = label(s.f, "", UD2(0, 60, 0, 13), UD2(0, 6, 1, -4), SZ.tiny, TH.C.TEXT, COND_F, V2(0, 1), LEFT)   -- 只在选中那格写
    s.tag.Name = "Tag"
    s.tag.ZIndex = 4
    s.tag.Visible = false
    s.tm = label(s.f, "", UD2(0, 40, 0, 13), UD2(1, -6, 1, -4), SZ.tiny, MUTE, MONO_F, V2(1, 1), RIGHT)   -- 冷却秒数
    s.tm.Name = "Secs"
    s.tm.ZIndex = 4
    s.line = frame(s.f, UD2(1, 0, 0, 2), UD2(0, 0, 1, 0), WHITE, 0.85, V2(0, 1))   -- 底边：装填 / 维修的进度条（平时不画）
    s.line.Name = "Line"
    s.line.ZIndex = 4
    s.line.Visible = false
    s.fill = frame(s.line, UD2(0, 0, 1, 0), nil, AMBER, 0)
    s.fill.ZIndex = 4
    s.kind, s.pic = nil, nil
    s.selK, s.bri, s.emptyT, s.nFlashT, s.lastN = 0, 1, -9, -9, nil
    s.c = {}   -- put：每个属性上次写的值
    s.x = 0
    slots[i] = s
    return s
  end

  -- 这辆车的弹药栏：主炮每种弹一格，别的武器一格，再加烟幕弹、维修 / 灭火
  local slotDef, slotKey = {}, nil
  local loadX = 0   -- 名牌右边「装填」写到哪（武器那几组的右边）
  -- 带了哪几种弹：服务器 Wt.lua 的 AmL 把这门炮所有弹种都写上（没带的 0 发）——出车以后出现过大于 0 发的就算带了（补给多出来的也算）
  local carriedBy = setmetatable({}, { __mode = "k" })   -- [车模型] = { [弹种] = true }
  local amlSeen = setmetatable({}, { __mode = "k" })     -- [车模型] = 上次解析过的 AmL 字串（没变就不再 gmatch：每帧都要问）
  local function carriedOf(em)
    if not em then return nil end
    local L = em:GetAttribute("AmL")
    if type(L) ~= "string" or L == "" then return nil end
    local c = carriedBy[em]
    if not c then
      c = {}
      carriedBy[em] = c
    end
    if amlSeen[em] ~= L then
      amlSeen[em] = L
      for k, n in string.gmatch(L, "([%w_]+):(%d+)") do if tonumber(n) > 0 then c[k] = true end end
    end
    return c
  end
  G.wtCarried = carriedOf   -- Drive 的 ammoList（Q 换弹）也只在带了的里面转
  -- 11-27 用户：「训练场有时候显示按4是切换射流 但是实际上切换不了」「如果我没有携带 就不要显示了吧」——这门炮的弹种原来全列出来、按位置编号，
  --   可车上只能打研究过的前 ModAmmo 种、带了的那几种（Drive ammoList / 服务器 Armor.lua 只认这些），按了换不过去。
  --   现在：没研究的、没带的不显示；剩下的弹和武器从 1 往下连着编（打光了的那格还在，发数红）
  local lastBuild = {}   -- 上一帧的（车型、研究到第几种、AmL 字串）：都没变就直接用排好的格子（不每帧拼键、排序）
  local function buildSlots(d, st)
    local em = st and st.em
    local nAm = em and em:GetAttribute("ModAmmo")
    local aml = em and em:GetAttribute("AmL")
    if lastBuild.d == d and lastBuild.nAm == nAm and lastBuild.aml == aml and lastBuild.em == em and slotKey then return slotDef end
    lastBuild.d, lastBuild.nAm, lastBuild.aml, lastBuild.em = d, nAm, aml, em
    nAm = (type(nAm) == "number") and math.max(1, nAm) or nil
    local car = carriedOf(em)
    local carKeys = {}
    for k in pairs(car or {}) do table.insert(carKeys, k) end
    table.sort(carKeys)
    local key = d.id .. ":" .. table.concat(d.weapons or {}, ",") .. ":" .. tostring(nAm) .. ":" .. table.concat(carKeys, "+")
    if slotKey == key then return slotDef end
    slotKey = key
    slotDef = {}
    for wi, wid in ipairs(d.weapons or {}) do
      local w = VD.W[wid]
      local list = BAL.GUN[wid]
      if list then
        for ai, k in ipairs(list) do
          local a = BAL.AMMO[k]
          local cls = a and a.cls or "ap"
          local usable = (nAm == nil or ai <= nAm) and (car == nil or car[k] == true)
          if usable then
            local _, _, tag = ammoInfo(k)
            table.insert(slotDef, { k = "am", wi = wi, wid = wid, am = k, icon = (cls == "atgm") and "sam" or cls, tag = tag })
          end
        end
      elseif w then
        local ic = (w.kind == "gun") and "mg" or ((w.kind == "sam" or w.kind == "atgm") and "sam" or ((w.kind == "arty" or (w.dmg or 0) >= 300) and "he" or "ac"))
        local tg = (w.kind == "atgm") and "ATGM" or ({ mg = "MG", sam = "SAM", he = "HE", ac = "AC" })[ic]
        table.insert(slotDef, { k = "w", wi = wi, wid = wid, icon = ic, tag = tg })
      end
    end
    for i, sd in ipairs(slotDef) do sd.num = (i <= 6) and i or nil end
    table.insert(slotDef, { k = "smoke", icon = "smoke", keyTxt = "M" })   -- 11-25 起烟幕是 M（X 是按住透视自己的车）
    table.insert(slotDef, { k = "fix", icon = "fix", keyTxt = "Y" })
    table.insert(slotDef, { k = "bino", icon = "bino", keyTxt = "C" })   -- 车长望远镜（用户 11-27，Drive / GunSight）
    if d.cat == "apc" or d.cat == "aa" then table.insert(slotDef, { k = "scout", icon = "scout", keyTxt = "G" }) end   -- 轻型车才能侦察（战雷）
    if d.cat ~= "aa" then table.insert(slotDef, { k = "arty", icon = "arty", keyTxt = "K" }) end   -- 防空车不能叫火炮
    for i = #slots + 1, #slotDef do newSlot(i) end
    -- 排：主炮弹 | 机枪 / 其他武器 | 工具，组间各空 10 像素、中间一道细线
    local x, prevG, nDiv = 0, nil, 0
    loadX = 0
    for i, s in ipairs(slots) do
      local sd = slotDef[i]
      s.f.Visible = sd ~= nil
      if sd then
        local grp = (sd.k == "am") and 1 or ((sd.k == "w") and 2 or 3)
        local wide = grp ~= 3
        if prevG and grp ~= prevG then
          local edge = x - GAP
          nDiv += 1
          local dv = divider(nDiv)
          dv.Visible = true
          dv.Position = UD2(0, edge + GRP + 0.5, 1, -8)
          x = edge + GRP * 2 + 1
        end
        prevG = grp
        s.kind, s.pic = nil, nil   -- 换车：下一帧重新装图
        s.img.Visible, s.ic.Visible = false, false
        s.c = {}                   -- put 的缓存清掉：这一格下一帧全部重写
        s.lastN = nil
        -- 机枪那格写「空格」（11-27 起按住空格打机枪；数字键照样能把它选成左键的武器）
        s.key.Text = (sd.k == "w" and sd.icon == "mg") and T("wtt.space") or (sd.num and tostring(sd.num) or (sd.keyTxt or ""))
        local kw = 4.5   -- 键位框跟着字宽：等宽 12 号一个英文字母约 7.5 像素、中文约 12.5（一个数字 12 × 12）
        for _, cp in utf8.codes(s.key.Text) do kw += (cp < 128) and 7.5 or 12.5 end
        kw = math.max(KEY, math.ceil(kw))
        s.keyBox.Size = UD2(0, kw, 0, KEY)
        s.rdy.Position = UD2(0, 4 + kw + 4, 0, 4 + KEY / 2)
        s.tag.Text = sd.tag or ""
        local sw = wide and AW or TW
        s.f.Size = UD2(0, sw, 0, AH)
        s.f.Position = UD2(0, x, 1, 0)
        -- 图片区：弹种 / 机枪格 x 0～92、工具格 x 2～58，都是 y 10～50（弹轴压在 y 30）
        s.img.Size = wide and UD2(0, 92, 0, IMG_H) or UD2(0, 56, 0, IMG_H)
        s.img.Position = UD2(0, wide and 0 or 2, 0, IMG_Y)
        s.ic.Position = UD2(0, wide and 46 or 30, 0, IMG_Y + IMG_H / 2)
        s.x = x
        x += sw + GAP
        if grp < 3 then loadX = x - GAP end
      end
    end
    for k = nDiv + 1, #dividers do dividers[k].Visible = false end
    local w = math.max(0, x - GAP)
    BAR.Size = UD2(0, w, 0, AH + PLATE)
    loadTxt.Position = UD2(0, (loadX > 0) and loadX or w, 0, 0)
    return slotDef
  end

  -- 这一格还剩几发（nil = 不计数）
  local amlStr, amlN = nil, {}   -- AmL 解析好的 [弹种] = 几发（字串变了才重新解析：每帧每格都要问）
  local function countOf(sd, st)
    local vs = G.S and G.S.veh
    local em = st and st.em
    if sd.k == "am" or sd.k == "w" then
      local am = vs and vs.ammo and vs.ammo[sd.wid]
      local tot = am and (am[1] + am[2]) or nil
      if sd.k == "am" and em then   -- ④ 配弹：每种弹各剩几发（服务器 Wt.lua 写 AmL = "m829a3:20,m830:12,…"）
        local L = em:GetAttribute("AmL")
        if L ~= amlStr then
          amlStr, amlN = L, {}
          if type(L) == "string" then for k, n in string.gmatch(L, "([%w_]+):(%d+)") do amlN[k] = tonumber(n) end end
        end
        local n = amlN[sd.am]
        if n then tot = n end
      end
      return tot
    elseif sd.k == "smoke" then
      return vs and vs.smoke or 0
    end
    return nil
  end
  local capBy = setmetatable({}, { __mode = "k" })   -- [车模型] = { [弹种 / 武器] = 出车以后见过的最多发数 }（剩两成变琥珀）
  local noAmmoT = -9

  -- 数字键：照底部弹药栏一格一个数（主炮的弹种在前，战雷那样 1 穿甲 / 2 破甲……）；Drive.lua 先问这里
  local usedSt = nil   -- 这一趟开的车画过战雷界面（电脑布局）：开着瞄准镜时数字键也照这个排
  G.wtKeySlot = function(st, i)
    if not (st and st.d and st == usedSt) then return false end
    local sd, si = nil, nil
    for j, x in ipairs(buildSlots(st.d, st)) do if x.num == i then sd, si = x, j break end end
    if not sd then return false end
    if countOf(sd, st) == 0 and slots[si] then   -- 打空了的：描边红闪两下、名牌写「无弹」
      slots[si].emptyT = os.clock()
      noAmmoT = os.clock()
    end
    st.wi = sd.wi
    if sd.k == "am" and G.driveAmmo then G.driveAmmo(sd.am) end   -- 换弹种：Drive 的 cycleAmmo（换了要重新装一发）
    return true
  end

  local barShownT, lastBarT = -9, nil
  -- 写实图这一排的状态：整排一起出、一格不行整排退回剪影（11-27 美术审查第 16 条：原来一排里写实图、剪影会混着）
  --   key 这辆车的格子；k 正在显示的那一套（1 / 2 倍）；state "wait" 模块还没到 / "decoding" 排队解着 / "ok" 都解好了 / "fallback" 整排剪影；
  --   need / gray：这一排要的彩色图、去色图的名字；nextK：屏幕跨过 850、要换另一套时，后台在解的那一套（解好了才换，旧的一直显示着）；
  --   badK[k]：那一套解不出（不再试，留着旧的）
  local row = { key = nil, k = 2, state = "wait", need = nil, gray = nil, okT = -9, nextK = nil, badK = {} }
  local retried = {}  -- [格子 key] = true：用不了 EditableImage 时，换到这辆车只再试一次
  -- 这一格可能用到的图：弹种 / 武器一张，工具格一张（维修那格起火时换灭火器：两张都要）；没有图返回 nil
  local function picNames(sd)
    if sd.k == "am" then
      local n = G.ammoPicName("ammo", sd.am)
      return n and { n } or nil
    elseif sd.k == "w" then
      local n = G.ammoPicName("w", sd.wid)
      return n and { n } or nil
    elseif sd.k == "fix" then
      local a, b = G.ammoPicName("tool", "fix"), G.ammoPicName("tool", "ext")
      return (a and b) and { a, b } or nil
    end
    local n = G.ammoPicName("tool", sd.icon)
    return n and { n } or nil
  end
  local function counted(sd) return sd.k == "am" or sd.k == "w" or sd.k == "smoke" end   -- 会打空：去色的也要
  -- 一套图（k 倍）排进解码队列：彩色的先（整排要等它们），去色的跟着（打空那一下不用现解）
  local function wantSet(k)
    for _, n in ipairs(row.need) do G.ammoPicWant(n, false, k) end
    for _, n in ipairs(row.gray) do G.ammoPicWant(n, true, k) end
  end
  -- 这一套解好了没有（withGray：去色的也算上——后台换套时等它们也好，免得打空的那格先闪一下彩色）：true 好了 / false 有一张解不出 / nil 还在解
  local function setDone(k, withGray)
    local done = true
    for pass = 1, withGray and 2 or 1 do
      for _, n in ipairs((pass == 1) and row.need or row.gray) do
        local r = G.ammoPic(n, pass == 2, k)
        if r == false then return false end
        if r == nil then done = false end
      end
    end
    return done or nil
  end
  -- wantK：按现在的屏幕该用哪一套（逻辑屏高 ≥ 850 用 2 倍、更矮的用 1 倍，见上面的说明）
  local function stepRow(def, t, wantK)
    if not G.ammoPicState then
      row.state = "fallback"
      return
    end
    if row.key ~= slotKey then   -- 换车 / 格子变了：整排重来（先空着，都解好了一起淡入）
      row.key, row.k, row.state, row.need, row.gray, row.names = slotKey, wantK, "wait", nil, nil, nil
      row.nextK, row.badK = nil, {}
      for _, s in ipairs(slots) do s.pic = nil end
      if G.ammoPicState() == "broken" and not retried[slotKey] then   -- 换车：用不了 EditableImage 的再试一次
        retried[slotKey] = true
        if G.ammoPicRetry then G.ammoPicRetry() end
      end
    elseif row.state ~= "ok" and row.k ~= wantK and row.state ~= "fallback" then
      row.k = wantK   -- 还没出图：直接改解另一套
      if row.state == "decoding" then wantSet(wantK) end
    elseif row.state == "ok" and wantK ~= row.k and row.nextK ~= wantK and not row.badK[wantK] then
      row.nextK = wantK   -- 只是屏幕跨过了 850：旧的那套先留着显示，新的一套在后台解（不清空、不重新淡入）
      wantSet(wantK)
    elseif row.nextK and wantK == row.k then
      row.nextK = nil     -- 又跨回来了
    end
    local stt = G.ammoPicState()
    if row.state == "wait" then
      if stt == "ready" then
        local color, gray, names = {}, {}, {}
        for i, sd in ipairs(def) do
          local ns = picNames(sd)
          if not ns then   -- 有一格没有图：整排用剪影
            row.state = "fallback"
            return
          end
          names[i] = ns   -- 每格的图名记下来（每帧不用再查、再建表）
          for _, n in ipairs(ns) do
            table.insert(color, n)
            if counted(sd) then table.insert(gray, n) end
          end
        end
        row.need, row.gray, row.names = color, gray, names
        wantSet(row.k)
        row.state = "decoding"
      elseif stt == "failed" or stt == "broken" then
        row.state = "fallback"
      end
    end
    if row.state == "decoding" or row.state == "ok" then
      G.ammoPicPump()   -- 每帧最多解一张
      if G.ammoPicState() == "broken" then
        row.state = "fallback"
        return
      end
      if row.state == "decoding" then
        local d = setDone(row.k)
        if d == false then
          row.state = "fallback"
          return
        elseif d then
          row.state, row.okT = "ok", t
        end
      elseif row.nextK then   -- 后台那一套：都解好了就换过去（每格的图名带着 @k，下一段逐格换图，不淡入）；解不出就留着旧的
        local d = setDone(row.nextK, true)
        if d == false then
          row.badK[row.nextK], row.nextK = true, nil
        elseif d then
          row.k, row.nextK = row.nextK, nil
        end
      end
    end
  end
  local function stepBar(st, I)
    local d = st.d
    local def = buildSlots(d, st)
    local f = st.fcs
    local em = st.em
    local fire = em and em:GetAttribute("WtF") == true
    local fix = em and em:GetAttribute("WtFix")
    local gunOk = not (em and em:GetAttribute("WtGun") == false)
    local t = os.clock()
    local dt = lastBarT and math.clamp(t - lastBarT, 0, 0.1) or 0
    lastBarT = t
    local fa = math.clamp((t - barShownT) / 0.15, 0, 1)   -- 整排淡入
    local function A(tr) return 1 - (1 - tr) * fa end
    local caps = em and capBy[em]
    if em and not caps then
      caps = {}
      capBy[em] = caps
    end
    stepRow(def, t, (cam.ViewportSize.Y >= 850) and 2 or 1)
    local picK = row.k   -- 正在显示的那一套
    local pa = math.clamp((t - row.okT) / 0.12, 0, 1)   -- 整排写实图解好那一下淡入 120 毫秒
    local curName, curType, curLoad = "", "", nil
    local gunDmg = false   -- 主炮坏了（有主炮弹种格的车）：名牌右边写一次「主炮损坏」
    for i, sd in ipairs(def) do
      local s = slots[i]
      local c = s.c
      local sel, empty, cnt = false, false, ""
      local ic = sd.icon
      local fillK, timeTxt = nil, ""
      local reloading, cool, dmg = false, false, false
      local tot = countOf(sd, st)
      if sd.k == "am" or sd.k == "w" then
        cnt = tot and tostring(tot) or "∞"
        empty = tot == 0
        if sd.k == "am" then
          local c0 = (f and f.am) or (BAL.GUN[sd.wid] and BAL.GUN[sd.wid][1])
          sel = st.wi == sd.wi and c0 == sd.am
          dmg = not gunOk
          gunDmg = gunDmg or dmg
          if sel then
            local nm, ty = ammoInfo(sd.am)
            curName, curType = nm, ty
          end
        else
          sel = st.wi == sd.wi
          if sel then curName, curType = T("vw." .. sd.wid), "" end
        end
        if sel and I and I.ready == false then   -- 装填：秒数只写一处（格子里不写；车外准星写着的时候名牌也不写，见下面）
          reloading = true
          fillK = math.clamp(I.relK or 0, 0, 1)
          curLoad = I.left or 0
        end
      elseif sd.k == "smoke" then
        cnt, empty = tostring(tot or 0), (tot or 0) <= 0
      elseif sd.k == "arty" then   -- 火炮支援：冷却（服务器时间）；侦察助攻多给的次数写在右上
        local cd = me:GetAttribute("WtArtyCd")
        local left = cd and (cd - workspace:GetServerTimeNow()) or 0
        local bonus = me:GetAttribute("WtArtyBonus")
        if left > 0 and not bonus then
          cool = true
          fillK, timeTxt = 1 - left / 120, string.format("%ds", math.ceil(left))
        end
        cnt = bonus and ("+" .. bonus) or ""
      elseif sd.k == "scout" then
        cnt = ""
      elseif sd.k == "bino" then   -- 望远镜开着：这格选中
        cnt = ""
        sel = st.binoc == true
      else   -- 维修 / 灭火：起火时换成灭火器；修的时候底边进度
        if fire then ic = "ext" end
        if fix then fillK = fix end
        cnt = ""
      end
      -- 剩两成变琥珀：按出车以后见过的最多发数算；补给加了一发白闪一下
      local capKey = sd.am or sd.wid or sd.k
      if tot and caps then
        caps[capKey] = math.max(caps[capKey] or 0, tot)
        if s.lastN and tot > s.lastN then s.nFlashT = t end
        s.lastN = tot
      end
      local low = tot and caps and caps[capKey] and caps[capKey] > 0 and tot <= caps[capKey] * 0.2
      -- 图：写实渲染图（AmmoPics，整排解好了才出）；打空了换去色的（还没解好先用彩色的）；整排退回时单色剪影
      local showPic = row.state == "ok"
      if showPic then
        local ns = row.names and row.names[i]
        local pname = ns and ((sd.k == "fix" and fire) and ns[2] or ns[1]) or nil
        local gray = (empty and pname ~= nil and G.ammoPic(pname, true, picK)) and true or false
        local want = pname and (pname .. (gray and "#g" or "") .. "@" .. picK) or nil
        if s.pic ~= want then
          s.pic = want
          local ok = pname ~= nil and G.ammoPicOn(s.img, pname, gray, picK) == true
          if ok then
            s.imgFade.Enabled = G.ammoPicFade(pname)
            c.imgTr, c.imgCol = nil, nil   -- 换了图：亮度、透明度重写
          else
            row.state = "fallback"   -- 有一格装不上：整排退回剪影
            showPic = false
          end
        end
        if showPic and empty and pname and G.ammoPic(pname, true, picK) == false then   -- 去色的解不出：也整排退回
          row.state = "fallback"
          showPic = false
        end
      end
      local showIcon = row.state == "fallback"
      put(c, "imgV", s.img, "Visible", showPic)
      put(c, "icV", s.ic, "Visible", showIcon)
      if showIcon and s.kind ~= ic then
        s.kind = ic
        icon(s.ic, ic)
        c.icTr = nil
      end
      -- 状态 → 样子（描边颜色 100 毫秒线性过渡；装填时图压暗到八成，装好 120 毫秒内回来）
      s.selK = math.clamp(s.selK + (sel and 1 or -1) * dt / 0.1, 0, 1)
      local briT = reloading and 0.8 or (sel and 1 or 0.9)
      if s.bri < briT then s.bri = math.min(briT, s.bri + dt / 0.12) else s.bri = math.max(briT, s.bri - dt / 0.1) end
      local unavailable = cool or (dmg and sd.k == "am")
      local imgTr = empty and 0.65 or (unavailable and 0.75 or 0)
      local stCol = WHITE:Lerp(AMBER, s.selK)
      local stTr = 0.85 + (0 - 0.85) * s.selK
      local et = t - s.emptyT   -- 按了打空的那格：红闪两下（各 100 毫秒）
      if et < 0.4 and (et < 0.1 or (et >= 0.2 and et < 0.3)) then stCol, stTr = PEN_NO, 0 end
      if sd.k == "fix" and fire then stCol, stTr = PEN_NO, 0 end   -- 起火：灭火那格红描边（不闪）
      put(c, "fT", s.f, "BackgroundTransparency", A(0.35))
      put(c, "stC", s.st, "Color", stCol)
      put(c, "stT", s.st, "Transparency", A(stTr))
      if showPic then
        local b = math.floor(s.bri * 100 + 0.5) / 100
        put(c, "imgCol", s.img, "ImageColor3", Color3.new(b, b, b))
        put(c, "imgTr", s.img, "ImageTransparency", 1 - (1 - A(imgTr)) * pa)
      elseif showIcon then
        local icTr = empty and 0.78 or (unavailable and 0.8 or (sel and 0 or 0.35))
        icTr = 1 - (1 - icTr) * fa
        if c.icTr ~= icTr then   -- 剪影的零件：透明度变了才挨个改
          c.icTr = icTr
          for _, q in ipairs(s.ic:GetDescendants()) do
            if q:IsA("Frame") and q.BackgroundColor3 == ICON then
              q:SetAttribute("Base", q:GetAttribute("Base") or q.BackgroundTransparency)
              q.BackgroundTransparency = 1 - (1 - q:GetAttribute("Base")) * (1 - icTr)
            elseif q:IsA("UIStroke") then
              q.Transparency = icTr
            end
          end
        end
      end
      -- 冷却：暗遮罩从上往下退（盖住还没走完的那一截）
      put(c, "maskV", s.mask, "Visible", cool)
      if cool then
        put(c, "maskS", s.mask, "Size", UD2(1, 0, 1 - math.floor(math.clamp(fillK or 0, 0, 1) * 200 + 0.5) / 200, 0))
        put(c, "maskT", s.mask, "BackgroundTransparency", A(0.3))
      end
      -- 右上：发数（白；剩两成琥珀；0 红）；主炮坏了发数照写、变暗（FAINT、透明 0.4）——「主炮损坏」只在名牌右边写一次
      --   （11-27 美术审查第二轮：原来 5 个弹种格都换成红字「损坏」，加上左下损伤图、「按 Y 维修」，同一件事说了 5 遍）
      local nDim = dmg and sd.k == "am"
      put(c, "nTx", s.n, "Text", cnt)
      put(c, "nCol", s.n, "TextColor3", nDim and FAINT or (empty and PEN_NO or (low and AMBER or TH.C.TEXT)))
      put(c, "nT", s.n, "TextTransparency", A(nDim and 0.4 or 0))
      put(c, "nS", s.n, "TextStrokeTransparency", A(0.45))
      local nf = t - s.nFlashT < 0.08
      put(c, "nBg", s.nBg, "BackgroundTransparency", nf and A(0.55) or 1)
      -- 左上键位框（主炮坏了变暗）；装好了键位框右边一个白点（选中、装好、有弹、炮能打）
      local keyDim = dmg and sd.k == "am"
      local keyCol = keyDim and FAINT or (sel and TH.C.TEXT or MUTE)
      put(c, "kCol", s.key, "TextColor3", keyCol)
      put(c, "kSCol", s.keyS, "Color", keyCol)
      put(c, "kT", s.key, "TextTransparency", A(keyDim and 0.4 or 0))
      put(c, "kS", s.key, "TextStrokeTransparency", A(0.45))
      put(c, "kST", s.keyS, "Transparency", A(keyDim and 0.5 or 0))
      local ready = sel and (sd.k == "am" or sd.k == "w") and not reloading and not empty and gunOk
      put(c, "rdyV", s.rdy, "Visible", ready)
      if ready then put(c, "rdyT", s.rdy, "BackgroundTransparency", A(0)) end
      -- 左下类型：只在选中那格写（别的格子名牌上都有）；右下：冷却秒数
      put(c, "tagV", s.tag, "Visible", sel and (s.tag.Text ~= ""))
      if sel then
        put(c, "tagT", s.tag, "TextTransparency", A(0))
        put(c, "tagS", s.tag, "TextStrokeTransparency", A(0.45))
      end
      put(c, "tmTx", s.tm, "Text", timeTxt)
      if timeTxt ~= "" then
        put(c, "tmT", s.tm, "TextTransparency", A(0))
        put(c, "tmS", s.tm, "TextStrokeTransparency", A(0.45))
      end
      -- 底边：只在装填 / 维修时当进度条（底下一道淡轨道）；平时不画，冷却只有遮罩
      local prog = (fillK ~= nil) and not cool and fillK < 1
      put(c, "lineV", s.line, "Visible", prog)
      if prog then
        put(c, "lineT", s.line, "BackgroundTransparency", A(0.85))
        put(c, "fillS", s.fill, "Size", UD2(math.floor(math.clamp(fillK, 0, 1) * 200 + 0.5) / 200, 0, 1, 0))
        put(c, "fillT", s.fill, "BackgroundTransparency", A(0))
      end
    end
    for k = 1, #dividers do put(plateC, "dv" .. k, dividers[k], "BackgroundTransparency", A(0.85)) end
    -- 名牌：型号（白 15）+「· 类型」（灰 13）；按了打空的那格：「无弹」（红）——内容变了才重新拼字串
    local noAm = t - noAmmoT < 1.2
    local pk = noAm and "\0" or (curName .. "\1" .. curType)
    if plateC.key ~= pk then
      plateC.key = pk
      local w = 0   -- 名牌后面那条暗底的宽：窄体 15 号一个英文字母约 7.5 像素、中文约 15；类型 13 号约 6.5
      if noAm then
        ammoName.Text = T("wtt.noAmmo")
        ammoName.TextColor3 = PEN_NO
        for _, cp in utf8.codes(ammoName.Text) do w += (cp < 128) and 7.5 or 15 end
      else
        ammoName.TextColor3 = TH.C.TEXT
        ammoName.Text = (curType ~= "") and string.format('%s<font size="%d" color="#%s">  ·  %s</font>', curName, SZ.small, MUTE_HEX, curType) or curName
        for _, cp in utf8.codes(curName) do w += (cp < 128) and 7.5 or 15 end
        if curType ~= "" then for _, cp in utf8.codes("  ·  " .. curType) do w += (cp < 128) and 6.5 or 13 end end
      end
      plateC.nameW = w
    end
    put(plateC, "nT", ammoName, "TextTransparency", A(0))
    put(plateC, "nS", ammoName, "TextStrokeTransparency", A(0.45))
    -- 名牌右边：主炮坏了写一次红字「主炮损坏」（窄体 13 号中文用粗体）；不然装填中写「装填 x.x s」（琥珀等宽 13）——
    --   车外准星在屏幕上时不写（它自己写着秒数 + 琥珀弧：同一件事不说两遍）；开镜、望远镜里没有那个准星，照写
    if I and I.p ~= nil and AIM.root.Visible then curLoad = nil end
    local lt = (not gunDmg) and curLoad and math.floor(curLoad * 10 + 0.5) or nil   -- 装填秒数：到 0.1 秒变了才重写
    local rk = gunDmg and -1 or lt
    if plateC.lt ~= rk then
      plateC.lt = rk
      if gunDmg then
        loadTxt.Text, loadTxt.TextColor3, loadTxt.Font = T("wtt.gunDmg"), PEN_NO, BOLD
      else
        loadTxt.Text, loadTxt.TextColor3, loadTxt.Font = lt and T("wtt.load", string.format("%.1f", lt / 10)) or "", AMBER, MONO_F
      end
    end
    put(plateC, "lT", loadTxt, "TextTransparency", A(0))
    put(plateC, "lS", loadTxt, "TextStrokeTransparency", A(0.45))
    local bw = ((plateC.nameW or 0) > 0) and (plateC.nameW + 26) or 0
    if rk then bw = math.max(bw, loadTxt.Position.X.Offset + 16) end
    put(plateC, "bgW", plateBg, "Size", UD2(0, math.ceil(bw), 0, 20))
    put(plateC, "bgV", plateBg, "Visible", bw > 0)
    put(plateC, "bgT", plateBg, "BackgroundTransparency", A(0.5))
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
  local shownT, lastVp, lastBarW = -9, nil, nil
  local function layout()
    local vp = cam.ViewportSize
    local bw = BAR.Size.X.Offset
    if vp == lastVp and bw == lastBarW then return end
    lastVp, lastBarW = vp, bw
    local ds = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.8, 1.25)
    diScale.Scale = ds
    -- 弹药栏按 1080p 设计：屏幕高 / 1080，夹在 0.85～1.4；底边上方 16 像素、水平居中——
    --   左下的损伤示意图（小地图右边）挡着的时候整排往右让开；屏幕窄得放不下再缩小
    local s = math.clamp(vp.Y / 1080, 0.85, 1.4)
    local diRight = 252 + 250 * ds + 12
    if bw > 0 and bw * s > vp.X - diRight - 12 then s = math.max(0.5, (vp.X - diRight - 12) / bw) end
    local left = vp.X / 2 - bw * s / 2
    barScale.Scale = s
    BAR.Position = UD2(0.5, math.max(0, diRight - left), 1, -16 * s)
  end
  -- I：{ p 炮指的点、o 炮口、relK / ready / left 装填、wid / w 选中的武器、am 弹种 }；没有炮（车上只有机枪的）I.p 是 nil：只画弹药栏、损伤图
  function G.wtTankStep(st, I)
    shownT = os.clock()
    usedSt = st
    if not gui.Enabled then barShownT = os.clock() end   -- 整排淡入 150 毫秒
    gui.Enabled = true
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
      -- 测距（用户 11-25「全部都做」⑤）：按 R 才有（只有历史模式）——有激光测距的马上准，
      --   没有的（豹 1、M60A1、BMP-1）车长估两秒、报个整 50 米的数（≈）；10 秒后作废
      do   -- 只有历史（11-27）：按 R 才测距
        local f = st.fcs
        if f and f.estimating then AIM.rng.Text = T("wtt.est")
        elseif f and f.R and (f.man or (f.laseT and t - f.laseT < 10)) then AIM.rng.Text = (f.est and "≈" or "") .. T("vh.m", f.R)
        elseif f and f.noRet and f.laseT and t - f.laseT < 3 then AIM.rng.Text = "----"
        else AIM.rng.Text = T("wtt.rkey") end
      end
    else
      AIM.root.Visible = false
    end
    local ok, err = pcall(stepBar, st, I)
    if not ok and G.showError then G.showError("战雷弹药栏：" .. tostring(err)) end
    layout()   -- 弹药栏排好（这辆车几格）以后再定大小、位置
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
