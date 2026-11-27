-- Roblox全面大战场（客户端）——开地面载具：位置在本地算（按地形贴地、坡太陡上不去、不会游的不下水、撞房子停），每秒 15 次报给服务器；
--   镜头：追尾（鼠标绕着车转），Shift / 右键进出炮长瞄准镜（镜头在瞄准镜的位置、顺着炮管看，滚轮 / Z 换倍率）；
--   瞄准镜四种光电模式（V 切换，开着镜 N 也行；没开镜 N 是 夜视 → 热成像 → 关，Night.lua）：昼光、夜视（绿色、颗粒、圆形目镜）、热成像白热（背景压暗、人和车发白光）、热成像黑热（反过来）——
--     热的东西用 Highlight 标出来：所有实体的样子在一个 Model 里（一个高亮），玩家角色各一个（最多 24 个，挑近的）
--   炮塔跟着准星转（有回转速度上限，炮有俯仰范围），炮弹有下坠（自动按距离抬一点）；左键开火、1 / 2 换武器、M 烟幕弹（X 也行）、F 下车
--   用户：坦克按 Shift 切换开镜；开镜画面上写着「按 V 切换光电模式」「按 M 释放烟雾弹」
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")

local Drive = {}

function Drive.init(G)
  local Map = require(RS:WaitForChild("Map"))
  local VD = require(RS:WaitForChild("VehDefs"))
  local TMods = require(RS:WaitForChild("TankMods"))   -- 坦克改装（用户 11-19）
  local BAL = require(RS:WaitForChild("Ballistics"))   -- 坦克炮的真实弹道、弹种（用户 11-22 晚：开镜开炮符合真实物理和火控）
  local WM = require(RS:WaitForChild("WtMods"))   -- 科技树改装：火控计算机哪一代、升级了几级（WtMods.FCS）
  local OPT = require(RS:WaitForChild("WtOptics"))   -- 观瞄按年代（用户 11-26）：夜视是哪一种、分划是哪一套、能切哪几种通道
  local TTr = require(RS:WaitForChild("TechTree"))
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local ui = G.ui
  local function T(k, ...) return G.T(k, ...) end

  local st = nil   -- 正在开的车
  G.drive, G.myVeh = nil, nil

  ---------------------------------------------------------------- 界面：车的仪表、瞄准镜

  local gui = Instance.new("ScreenGui")
  gui.Name = "Drive"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 5
  gui.Parent = me:WaitForChild("PlayerGui")

  local panel = ui.frame(gui, UDim2.fromOffset(420, 76), UDim2.new(0.5, 0, 1, -24), RGB(12, 16, 20), 0.3, Vector2.new(0.5, 1))   -- 下面让出操作说明那一行（UI.lua）
  panel.Visible = false
  local vName = ui.label(panel, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 6), 16, Color3.new(1, 1, 1), Enum.Font.BuilderSansBold, nil, Enum.TextXAlignment.Left)
  local hpBg = ui.frame(panel, UDim2.new(1, -20, 0, 8), UDim2.fromOffset(10, 30), RGB(0, 0, 0), 0.4)
  local hpBar = ui.frame(hpBg, UDim2.fromScale(1, 1), nil, RGB(90, 210, 110), 0)
  local vInfo = ui.label(panel, "", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 42), 14, Color3.new(1, 1, 1), Enum.Font.BuilderSansMedium, nil, Enum.TextXAlignment.Left)
  local relBg = ui.frame(panel, UDim2.new(1, -20, 0, 4), UDim2.fromOffset(10, 63), RGB(0, 0, 0), 0.5)
  local relBar = ui.frame(relBg, UDim2.fromScale(0, 1), nil, RGB(240, 200, 80), 0)
  ui.flatPanel(panel, { hp = hpBg, rel = relBg, name = vName })   -- 跟新界面一个样子（UI.lua）

  local cross = ui.label(gui, "◯", UDim2.fromOffset(30, 30), UDim2.fromScale(0.5, 0.5), 22, Color3.new(1, 1, 1), Enum.Font.BuilderSansBold, Vector2.new(0.5, 0.5))
  cross.TextStrokeTransparency = 0.4
  cross.Visible = false
  local gunMark = ui.label(gui, "+", UDim2.fromOffset(26, 26), UDim2.fromScale(0.5, 0.5), 26, RGB(255, 210, 80), Enum.Font.BuilderSansBold, Vector2.new(0.5, 0.5))
  gunMark.TextStrokeTransparency = 0.3
  gunMark.Visible = false

  -- 瞄准镜：圆形目镜（昼光、夜视）或者长方形屏幕（热成像）；分划、测距、模式、倍率；夜视 / 热成像的颗粒
  local sight = Instance.new("Frame")
  sight.Size = UDim2.fromScale(1, 1)
  sight.BackgroundTransparency = 1
  sight.Visible = false
  sight.Parent = gui
  -- 用户 11-27（照战雷、发了截图）：全屏开镜、细黑线分划按密位随倍率缩放、表尺、方位刻度、炮管指向；车长望远镜——都在 GunSight.lua 画
  --   （下面原来的圆形目镜、热像框、红色分划和镜下读数留着不显示：车里的辅助瞄准镜 Interior 还在用一部分）
  local GS = require(script.Parent:WaitForChild("GunSight")).new(G, sight, gui)
  G.gunSight = GS
  local eyepiece = Instance.new("Frame")   -- 圆：里面透明，外面一圈很粗的黑描边把四角盖住
  eyepiece.Name = "Eyepiece"
  eyepiece.AnchorPoint = Vector2.new(0.5, 0.5)
  eyepiece.Position = UDim2.fromScale(0.5, 0.5)
  eyepiece.Size = UDim2.fromScale(0.9, 0.9)
  eyepiece.BackgroundTransparency = 1
  eyepiece.Parent = sight
  local asp = Instance.new("UIAspectRatioConstraint")
  asp.AspectRatio = 1
  asp.Parent = eyepiece
  local ec = Instance.new("UICorner")
  ec.CornerRadius = UDim.new(0.5, 0)
  ec.Parent = eyepiece
  local es = Instance.new("UIStroke")
  es.Thickness = 900
  es.Color = Color3.new(0, 0, 0)
  es.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
  es.Parent = eyepiece
  local screenBox = Instance.new("Frame")   -- 热成像：屏幕的黑边框
  screenBox.AnchorPoint = Vector2.new(0.5, 0.5)
  screenBox.Position = UDim2.fromScale(0.5, 0.5)
  screenBox.Size = UDim2.fromScale(0.86, 0.8)
  screenBox.BackgroundTransparency = 1
  screenBox.Parent = sight
  local ss = Instance.new("UIStroke")
  ss.Thickness = 600
  ss.Color = RGB(8, 8, 8)
  ss.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
  ss.Parent = screenBox
  -- 分划：中心十字、两边的横线、测距刻度（照截图的样子）
  --   用户 11-24：「坦克开镜视角……带着光晕的红色准心，像钢铁猛兽一样」——LED 照明的红分划：每条线后面垫两层更宽、更透明的红色（光晕），
  --   数字也带一圈红色的发光描边；昼光、夜视、热像都是红的（车里的分划照明旋钮：白天亮红、夜间暗红）
  local RET = RGB(255, 46, 32)
  local RET_DIM = RGB(190, 34, 24)
  local reticle = Instance.new("Frame")
  reticle.Size = UDim2.fromOffset(300, 120)
  reticle.AnchorPoint = Vector2.new(0.5, 0.5)
  reticle.Position = UDim2.fromScale(0.5, 0.5)
  reticle.BackgroundTransparency = 1
  reticle.Parent = sight
  local retParts, retHalo = {}, {}
  local function halo(size, pos, grow, tr)
    local h = ui.frame(reticle, UDim2.new(size.X.Scale, size.X.Offset + grow, size.Y.Scale, size.Y.Offset + grow), pos, RET, tr, Vector2.new(0.5, 0.5))
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, math.ceil(grow / 2) + 1)
    c.Parent = h
    table.insert(retHalo, { f = h, t = tr })
    return h
  end
  local function rl(size, pos)
    halo(size, pos, 12, 0.9)
    halo(size, pos, 5, 0.68)
    local f = ui.frame(reticle, size, pos, RET, 0, Vector2.new(0.5, 0.5))
    table.insert(retParts, f)
    return f
  end
  rl(UDim2.fromOffset(40, 2), UDim2.new(0.5, -110, 0.5, 0))
  rl(UDim2.fromOffset(40, 2), UDim2.new(0.5, 110, 0.5, 0))
  rl(UDim2.fromOffset(26, 2), UDim2.new(0.5, -56, 0.5, -10))
  rl(UDim2.fromOffset(26, 2), UDim2.new(0.5, 56, 0.5, -10))
  rl(UDim2.fromOffset(26, 2), UDim2.new(0.5, -56, 0.5, 10))
  rl(UDim2.fromOffset(26, 2), UDim2.new(0.5, 56, 0.5, 10))
  rl(UDim2.fromOffset(2, 26), UDim2.new(0.5, 0, 0.5, -26))
  rl(UDim2.fromOffset(2, 26), UDim2.new(0.5, 0, 0.5, 26))
  -- 中心的小圈：一圈细线 + 外面一圈更粗、更透明的（光晕），圈里面不填（别挡住瞄的东西）
  local dotHalo = ui.frame(reticle, UDim2.fromOffset(10, 10), UDim2.fromScale(0.5, 0.5), RET, 1, Vector2.new(0.5, 0.5))
  local dhs = Instance.new("UIStroke")
  dhs.Color = RET
  dhs.Thickness = 5
  dhs.Transparency = 0.75
  dhs.Parent = dotHalo
  local dhc = Instance.new("UICorner")
  dhc.CornerRadius = UDim.new(0.5, 0)
  dhc.Parent = dotHalo
  local dot = ui.frame(reticle, UDim2.fromOffset(10, 10), UDim2.fromScale(0.5, 0.5), RET, 1, Vector2.new(0.5, 0.5))
  table.insert(retParts, dot)
  local dotStroke = Instance.new("UIStroke")
  dotStroke.Color = RET
  dotStroke.Thickness = 1.5
  dotStroke.Parent = dot
  local dc = Instance.new("UICorner")
  dc.CornerRadius = UDim.new(0.5, 0)
  dc.Parent = dot
  -- 各年代的分划（用户 11-26「不同时期的坦克开镜不一样」，WtOptics.RET）：上面那套是数字火控（dig / hk）；
  --   sov 苏式 TSh / TPD（^ 形瞄准标、两边提前量刻度、左上各弹种表尺、左下测距曲线），nato 早期弹道（细十字、下面一排落点横线），
  --   lrf 激光测距（方框瞄准标）——线都登记进 retParts / retHalo（分划照明、亮度旋钮照旧管它们），数字登记进 retTexts
  local RETS = { dig = reticle, hk = reticle }
  local retTexts = {}
  local retPtr = {}   -- 光学分划的距离指针：[分划] = { f = 指针, y = 距离（米）→ 像素 }
  local function retBox(name)
    local f = Instance.new("Frame")
    f.Name = "Ret_" .. name
    f.Size = UDim2.fromOffset(460, 380)
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.fromScale(0.5, 0.5)
    f.BackgroundTransparency = 1
    f.Visible = false
    f.Parent = sight
    RETS[name] = f
    return f
  end
  local function seg(par, x, y, w, h, rot)   -- 一根分划线：中心在分划中心偏 (x, y) 像素，宽 w 高 h，顺时针转 rot 度
    local pos = UDim2.new(0.5, x, 0.5, y)
    for _, g in ipairs({ { 10, 0.9 }, { 4, 0.7 } }) do
      local hf = ui.frame(par, UDim2.fromOffset(w + g[1], h + g[1]), pos, RET, g[2], Vector2.new(0.5, 0.5))
      hf.Rotation = rot or 0
      local c = Instance.new("UICorner")
      c.CornerRadius = UDim.new(0, math.ceil(g[1] / 2) + 1)
      c.Parent = hf
      table.insert(retHalo, { f = hf, t = g[2] })
    end
    local f = ui.frame(par, UDim2.fromOffset(w, h), pos, RET, 0, Vector2.new(0.5, 0.5))
    f.Rotation = rot or 0
    table.insert(retParts, f)
    return f
  end
  local function num(par, s0, x, y, ts)
    local t = ui.label(par, s0, UDim2.fromOffset(40, 14), UDim2.new(0.5, x, 0.5, y), ts or 12, RET, Enum.Font.RobotoMono, Vector2.new(0.5, 0.5))
    table.insert(retTexts, t)
    return t
  end
  do   -- sov：^ 形瞄准标（尖在瞄准点）、两边横线和提前量刻度、左上两列表尺（穿甲 / 榴弹，单位百米）、左下测距曲线（目标高 2.7 米）
    local R = retBox("sov")
    seg(R, -7, 11, 26, 2, 122.5)
    seg(R, 7, 11, 26, 2, 57.5)
    for sx = -1, 1, 2 do
      seg(R, sx * 96, 0, 120, 2)
      for i = 1, 5 do seg(R, sx * (36 + i * 20), 5, 2, 8) end
    end
    local zh = G.lang ~= "en"
    for c, lab in ipairs({ zh and "穿" or "AP", zh and "榴" or "HE" }) do
      local x = -200 + (c - 1) * 34
      seg(R, x, -105, 2, 120)
      num(R, lab, x, -175, 13)
      for i = 0, 5 do
        local y = -165 + i * 24
        seg(R, x + 5, y, 10, 2)
        if c == 1 then num(R, tostring(i * 4), x - 18, y, 11) end
      end
    end
    -- 表尺指针：一根横线跨两列表尺，停在装定的距离上（真车炮长摇表尺手轮挪这根线；光学年代没有数字读数，距离看它）
    local ptr = Instance.new("Frame")
    ptr.Name = "RangePtr"
    ptr.Size = UDim2.fromOffset(0, 0)
    ptr.Position = UDim2.new(0.5, 0, 0.5, -165)
    ptr.BackgroundTransparency = 1
    ptr.Parent = R
    seg(ptr, -183, 0, 62, 2)
    seg(ptr, -219, -3, 9, 2, 35)
    seg(ptr, -219, 3, 9, 2, -35)
    retPtr.sov = { f = ptr, y = function(m) return -165 + math.clamp(m, 0, 2000) * 0.06 end }
    seg(R, -140, 128, 120, 2)   -- 测距曲线：底线 + 一排越来越矮的竖线（离得越远目标越矮）
    for i, r in ipairs({ { -196, 46, "10" }, { -172, 32, "15" }, { -148, 23, "20" }, { -124, 16, "30" }, { -100, 12, "40" } }) do
      seg(R, r[1], 128 - r[2] / 2, 2, r[2])
      num(R, r[3], r[1], 128 - r[2] - 10, 10)
    end
  end
  do   -- nato：细十字（中间留空）、下面一排各距离的落点横线（百米）、横线上的提前量刻度
    local R = retBox("nato")
    seg(R, 0, -85, 1.5, 150)
    for sx = -1, 1, 2 do
      seg(R, sx * 95, 0, 170, 1.5)
      for i = 1, 4 do seg(R, sx * (i * 32), -4, 1.5, 8) end
    end
    seg(R, 0, 78, 1.5, 120)
    local DROP = { { 18, 34, "4" }, { 40, 30, "8" }, { 66, 26, "12" }, { 96, 22, "16" }, { 130, 18, "20" } }
    for i, r in ipairs(DROP) do
      seg(R, 0, r[1], r[2], 2)
      num(R, r[3], r[2] / 2 + 16, r[1], 11)
    end
    -- 左边一个 > 指着装定距离那一档落点线（两档之间按距离插）
    local ptr = Instance.new("Frame")
    ptr.Name = "RangePtr"
    ptr.Size = UDim2.fromOffset(0, 0)
    ptr.Position = UDim2.new(0.5, 0, 0.5, 18)
    ptr.BackgroundTransparency = 1
    ptr.Parent = R
    seg(ptr, -30, -3, 9, 1.5, 35)
    seg(ptr, -30, 3, 9, 1.5, -35)
    retPtr.nato = { f = ptr, y = function(m)
      local hm = math.clamp(m, 0, 2000) / 100
      local x0, y0 = 0, 0
      for _, r in ipairs(DROP) do
        local x1 = tonumber(r[3])
        if hm <= x1 then return y0 + (r[1] - y0) * (hm - x0) / (x1 - x0) end
        x0, y0 = x1, r[1]
      end
      return y0
    end }
  end
  do   -- lrf：方框瞄准标（四边各一根、角上留空）、两边横线、下面一根竖线
    local R = retBox("lrf")
    seg(R, 0, -11, 14, 2)
    seg(R, 0, 11, 14, 2)
    seg(R, -11, 0, 2, 14)
    seg(R, 11, 0, 2, 14)
    for sx = -1, 1, 2 do seg(R, sx * 95, 0, 140, 2) end
    seg(R, 0, 74, 2, 100)
  end
  -- 主动红外的探照灯圈：灯照得到的那一圈亮，外面压黑（只在主动红外档）
  local irBeam = Instance.new("Frame")
  irBeam.Name = "IrBeam"
  irBeam.AnchorPoint = Vector2.new(0.5, 0.5)
  irBeam.Position = UDim2.fromScale(0.5, 0.5)
  irBeam.Size = UDim2.fromScale(0.42, 0.42)
  irBeam.BackgroundTransparency = 1
  irBeam.Visible = false
  irBeam.Parent = sight
  do
    local a = Instance.new("UIAspectRatioConstraint")
    a.AspectRatio = 1
    a.Parent = irBeam
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = irBeam
    local st0 = Instance.new("UIStroke")
    st0.Thickness = 700
    st0.Color = Color3.new(0, 0, 0)
    st0.Transparency = 0.18
    st0.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    st0.Parent = irBeam
  end
  -- 第一代热像的扫描线（一道道横线）
  local scan = Instance.new("Frame")
  scan.Name = "ThScan"
  scan.Size = UDim2.fromScale(1, 1)
  scan.BackgroundTransparency = 1
  scan.Visible = false
  scan.Parent = sight
  for i = 0, 240 do
    local l = ui.frame(scan, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 0, i * 4), RGB(0, 0, 0), 0.72)
    l.Name = "L"
  end
  local blur = Instance.new("BlurEffect")   -- 热像分辨率低：画面糊一点（代越老越糊）
  blur.Name = "SightBlur"
  blur.Size = 0
  blur.Enabled = false
  blur.Parent = Lighting
  local rangeText = ui.label(sight, "", UDim2.fromOffset(200, 30), UDim2.new(0.5, 0, 0.5, 150), 26, RET, Enum.Font.RobotoMono, Vector2.new(0.5, 0.5))
  local modeText = ui.label(sight, "", UDim2.fromOffset(260, 22), UDim2.new(0.5, 0, 0.5, -180), 16, RET, Enum.Font.RobotoMono, Vector2.new(0.5, 0.5))
  local zoomText = ui.label(sight, "", UDim2.fromOffset(120, 22), UDim2.new(0.5, 200, 0.5, 150), 16, RET, Enum.Font.RobotoMono, Vector2.new(0.5, 0.5))
  -- 火控显示（照钢铁猛兽 / 真车主瞄准镜下沿那一行）：弹种、测距（没测距是战斗瞄准距离，前面写 BS；没回波 ----）、待发方块（装好弹是实心）
  local ammoText = ui.label(sight, "", UDim2.fromOffset(150, 24), UDim2.new(0.5, -190, 0.5, 150), 18, RET, Enum.Font.RobotoMono, Vector2.new(0.5, 0.5))
  ammoText.Name = "FcsAmmo"
  rangeText.Name = "FcsRange"
  local readyBox = ui.frame(sight, UDim2.fromOffset(15, 15), UDim2.new(0.5, 118, 0.5, 150), RET, 0, Vector2.new(0.5, 0.5))
  readyBox.Name = "FcsReady"
  -- 多回波指示（真车主瞄准镜：一次激光打到好几个东西——草丛、烟、树后面的车——距离数字上面一道横杠；首 / 末回波开关选用哪一个）
  local multiBar = ui.frame(sight, UDim2.fromOffset(64, 3), UDim2.new(0.5, 0, 0.5, 133), RET, 0, Vector2.new(0.5, 0.5))
  multiBar.Name = "FcsMulti"
  multiBar.Visible = false
  -- 火控状态（方式不是正常、稳定器关、激光保险、炮口基准该更新了）：分划上方一行
  local fcsText = ui.label(sight, "", UDim2.fromOffset(420, 20), UDim2.new(0.5, 0, 0.5, 118), 15, RET, Enum.Font.RobotoMono, Vector2.new(0.5, 0.5))
  fcsText.Name = "FcsStatus"
  local readyStroke = Instance.new("UIStroke")
  readyStroke.Color = RET
  readyStroke.Thickness = 1.5
  readyStroke.Parent = readyBox
  -- 镜里的操作提示（左上角两行大字 + 底下一行）：V 切换光电模式（写着现在是哪种）、M 释放烟雾弹（还剩几发）、Shift 退出、Z 倍率
  local hintBox = ui.frame(sight, UDim2.fromOffset(440, 100), UDim2.new(0, 28, 0, 96), RGB(0, 0, 0), 0.55)   -- 11-27：底下那行键位说明也挪进来（底下是弹药栏、损伤图）
  hintBox.Name = "SightHints"
  local hintV = ui.label(hintBox, "", UDim2.new(1, -16, 0, 28), UDim2.fromOffset(10, 4), 18, RGB(235, 240, 235), Enum.Font.BuilderSansBold)
  local hintM = ui.label(hintBox, "", UDim2.new(1, -16, 0, 28), UDim2.fromOffset(10, 34), 18, RGB(235, 240, 235), Enum.Font.BuilderSansBold)
  hintV.Name, hintM.Name = "HintOptic", "HintSmoke"
  hintV.TextXAlignment, hintM.TextXAlignment = Enum.TextXAlignment.Left, Enum.TextXAlignment.Left
  local hintLine = ui.label(hintBox, "", UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 62), 13, RGB(205, 212, 205), Enum.Font.BuilderSans)
  hintLine.TextWrapped = true
  hintLine.TextXAlignment = Enum.TextXAlignment.Left
  hintLine.TextYAlignment = Enum.TextYAlignment.Top
  hintLine.Name = "HintLine"
  local grain = Instance.new("Frame")
  grain.Size = UDim2.fromScale(1, 1)
  grain.BackgroundTransparency = 1
  grain.Parent = sight
  local dots = {}
  for i = 1, 90 do
    local g = ui.frame(grain, UDim2.fromOffset(2, 2), UDim2.new(), RGB(255, 255, 255), 0.7)
    dots[i] = g
  end

  -- 画面效果
  local cc = Instance.new("ColorCorrectionEffect")
  cc.Name = "SightCC"
  cc.Enabled = false
  cc.Parent = Lighting
  G.sightCC = cc
  local MODES = { "day", "nv", "whot", "bhot", "ir" }   -- 5 主动红外（WtOptics：六七十年代的车）；每辆车能切哪几种看 st.allow
  local ZOOMS0 = { 20, 7 }   -- 瞄准镜视场（度）：约 3.5×、10×
  -- 各型的视场（VehDefs 的 sightZoom：昼光、热像各几档倍率）：M1A2 SEPv2 第二代前视红外热像 3 / 6 / 13 / 25 / 50 倍、昼光 3 / 10 倍
  local ZOOMS = ZOOMS0
  local function zoomList()
    local z = st and st.d and st.d.sightZoom
    if not z then return ZOOMS0 end
    local th = (st.mode or 1) ~= 1   -- 夜视通道（微光、主动红外、热像）按 sightZoom.th 的倍率（真车的夜视镜倍率和昼光不一样）
    local mags = (th and z.th) or z.day or { 3.5, 10 }
    local key = (th and "th" or "day")
    z._fov = z._fov or {}
    if not z._fov[key] then
      local t = {}
      for i, m in ipairs(mags) do t[i] = 70 / m end
      z._fov[key] = t
    end
    return z._fov[key]
  end
  local function syncZooms()
    ZOOMS = zoomList()
    if st then st.zoom = math.clamp(st.zoom or 1, 1, #ZOOMS) end
  end
  local hl = {}   -- 热成像的高亮
  local function clearHl()
    for _, h in ipairs(hl) do h:Destroy() end
    hl = {}
  end
  local function newHl(adornee, color)
    local h = Instance.new("Highlight")
    h.Adornee = adornee
    h.FillColor = color
    h.FillTransparency = 0.08
    h.OutlineColor = color
    h.OutlineTransparency = 0.5
    h.DepthMode = Enum.HighlightDepthMode.Occluded
    h.Parent = cam   -- 镜头下面的东西只在本机
    table.insert(hl, h)
    return h
  end
  -- 热的东西：所有实体（一个 Model）+ 最近的 24 个别的玩家
  local function refreshHl(color)
    clearHl()
    if G.viewFolder then newHl(G.viewFolder, color) end
    local list = {}
    local cp = cam.CFrame.Position
    for _, pl in ipairs(Players:GetPlayers()) do
      local ch = pl.Character
      local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
      if pl ~= me and hrp then table.insert(list, { ch, (hrp.Position - cp).Magnitude }) end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    for i = 1, math.min(24, #list) do newHl(list[i][1], color) end
  end

  local function applyMode()
    if not st or not st.sight or G.interiorOptic then   -- 车里换成别的光学设备（辅助瞄准镜，Interior.lua）：它自己画分划、调颜色
      cc.Enabled = false
      blur.Enabled = false
      clearHl()
      sight.Visible = false
      G.sightNv = false
      return
    end
    sight.Visible = true
    syncZooms()
    local m = MODES[st.mode]
    -- 观瞄打坏了（WtVfx.lua，服务器 Wt.lua 的 optics 模块，11-26）：热成像通道没了，只剩昼光 / 微光
    if G.opticsDead and G.opticsDead() and (m == "whot" or m == "bhot") then m = "day" end
    G.sightNv = m == "nv" or m == "ir"   -- 镜里的夜视档：昼夜（DayNight.lua）照夜视仪那样增亮（夜视仪开着镜时让出画面，增亮原来也跟着撤了）
    local thermal = m == "whot" or m == "bhot"
    -- 用户 11-27（截图「这个样子」）：全屏，不套圆形目镜 / 热像屏幕框；分划换成 GunSight 画的细线（照真镜子、按密位）
    eyepiece.Visible = false
    screenBox.Visible = false
    -- 年代（WtOptics）：分划、热像的代、主动红外的探照灯圈
    local kit = st.kit or { ret = "dig", nv = "th2" }
    local ret = kit.ret or "dig"
    reticle.Visible = false
    for _, f in pairs(RETS) do f.Visible = false end
    GS.mode(m, kit, st)
    local NVd = OPT.NV[kit.nv or ""] or {}
    irBeam.Visible = m == "ir"
    scan.Visible = thermal and NVd.lines == true
    blur.Enabled = thermal and (NVd.blur or 0) > 0
    blur.Size = thermal and (NVd.blur or 0) or 0
    -- 光学年代的分划没有数字读数（测距、弹种、待发、状态那一行是数字火控的）——11-27 起读数在 GunSight 画，这里原来那几行收起来
    local digital = (ret == "dig" or ret == "hk" or ret == "lrf")
    st.kitDigital = digital
    ammoText.Visible, readyBox.Visible, fcsText.Visible, rangeText.Visible, multiBar.Visible = false, false, false, false, false
    modeText.Visible, zoomText.Visible = false, false   -- 光电模式写在左上的提示框里（[V] 切换光电模式：…）
    grain.Visible = m ~= "day"
    cc.Enabled = true
    local retCol = st.retNight and RET_DIM or RET   -- 红分划（钢铁猛兽那样）：分划照明旋钮白天亮红、夜间暗红
    if m == "day" then
      cc.Saturation, cc.Contrast, cc.Brightness, cc.TintColor = -0.1, 0.08, 0, Color3.new(1, 1, 1)
      clearHl()
    elseif m == "nv" then
      cc.Saturation, cc.Contrast, cc.Brightness, cc.TintColor = -1, 0.35, 0.06, RGB(120, 255, 140)
      clearHl()
    elseif m == "ir" then   -- 主动红外：红外变像管的绿、暗、反差大（只有探照灯那一圈看得清）
      cc.Saturation, cc.Contrast, cc.Brightness, cc.TintColor = -1, 0.42, -0.06, RGB(150, 236, 168)
      clearHl()
    elseif m == "whot" then
      cc.Saturation, cc.Contrast, cc.Brightness, cc.TintColor = -1, 0.45, -0.32, RGB(225, 225, 225)
      refreshHl(Color3.new(1, 1, 1))
    else
      cc.Saturation, cc.Contrast, cc.Brightness, cc.TintColor = -1, 0.25, 0.22, RGB(235, 235, 235)
      refreshHl(Color3.new(0, 0, 0))
    end
    -- 热像仪的增益（对比度）、电平（亮度）：炮长控制面板上的两个旋钮（车里 Interior：st.thGain / st.thLevel，0～4，2 是中间）
    if m == "whot" or m == "bhot" then
      cc.Contrast += (NVd.gain or 0)   -- 一代热像反差低、三代高
      cc.Contrast += ((st.thGain or 2) - 2) * 0.12
      cc.Brightness += ((st.thLevel or 2) - 2) * 0.07
    end
    -- 分划照明（白天的光学通道：夜里拨到红色照明）、分划亮度、符号亮度（面板上的旋钮：0 最亮 … 3 最暗 / 关）
    local RB = ({ 0, 0.25, 0.5, 0.75 })[(st.retLvl or 0) + 1] or 0
    local SB = ({ 0, 0.3, 0.6, 1 })[(st.symLvl or 0) + 1] or 0
    for _, f in ipairs(retParts) do f.BackgroundColor3 = retCol f.BackgroundTransparency = (f == dot) and 1 or RB end
    -- 光晕跟着分划亮度：调暗了光晕也淡；夜间照明（暗红）光晕再淡一点
    local hk = (1 - RB) * (st.retNight and 0.7 or 1)
    for _, h in ipairs(retHalo) do
      h.f.BackgroundColor3 = retCol
      h.f.BackgroundTransparency = 1 - (1 - h.t) * hk
    end
    dhs.Color, dhs.Transparency = retCol, 1 - 0.25 * hk
    dotStroke.Color = retCol
    dotStroke.Transparency = RB
    for _, l in ipairs(retTexts) do l.TextColor3 = retCol l.TextTransparency = SB end   -- 年代分划上的数字（表尺、测距曲线）
    for _, l in ipairs({ rangeText, modeText, zoomText, ammoText, fcsText }) do   -- 字也带一圈红色的光
      l.TextStrokeColor3 = retCol
      l.TextStrokeTransparency = 1 - (1 - SB) * 0.45 * (st.retNight and 0.7 or 1)
    end
    rangeText.TextColor3, modeText.TextColor3, zoomText.TextColor3, ammoText.TextColor3 = retCol, retCol, retCol, retCol
    rangeText.TextTransparency, modeText.TextTransparency, zoomText.TextTransparency, ammoText.TextTransparency, fcsText.TextTransparency = SB, SB, SB, SB, SB
    fcsText.TextColor3, multiBar.BackgroundColor3, multiBar.BackgroundTransparency = retCol, retCol, SB
    readyBox.BackgroundColor3, readyStroke.Color = retCol, retCol
    modeText.Text = T("sight." .. m) .. ((thermal and NVd.short) and ("  ·  " .. ((G.lang == "en") and NVd.short[2] or NVd.short[1])) or "")
    for _, g in ipairs(dots) do g.BackgroundColor3 = (m == "nv") and RGB(200, 255, 200) or Color3.new(1, 1, 1) end
  end

  -- 自己的车的样子不放在实体的大 Model 里（热成像整个高亮时会把镜头所在的车也涂白）
  local ownBox = Instance.new("Model")
  ownBox.Name = "OwnVeh"
  ownBox.Parent = workspace
  local function ownModel()
    local v = st and G.views and G.views[st.em]
    return v and v.model
  end
  -- 自己的车：坐进瞄准镜时藏起来（镜头在车里）
  local function ownVisible(on)
    local v = st and G.views and G.views[st.em]
    if not v or not v.M then return end
    for _, it in ipairs(v.M.parts) do
      local p = it[1]
      if p:IsA("BasePart") then p.LocalTransparencyModifier = on and 0 or 1 end
    end
  end

  ---------------------------------------------------------------- 开车

  local function findEnt(id)
    local f = workspace:FindFirstChild("Ents")
    if not f then return nil end
    for _, em in ipairs(f:GetChildren()) do
      if em:GetAttribute("EntId") == id then return em end
    end
    return nil
  end

  -- 车底 CFrame：按四个角的地面高度定俯仰、侧倾；在水里（两栖）浮着
  local function baseAt(d, pos, yaw, carried)
    local face = V(-math.sin(yaw), 0, -math.cos(yaw))
    local right = V(-face.Z, 0, face.X)
    if carried then   -- 站在气垫艇上：车底就是艇的甲板（离水面 / 沙滩一层气垫），跟着艇晃；转弯往外侧倾、加速抬头
      local t = os.clock()
      local g = math.max(Map.height(pos.X, pos.Z), 0)
      local p = V(pos.X, g + VD.LCAC.deck + math.sin(t * 1.4) * 0.12, pos.Z)
      local hv = st and st.hv
      local roll = hv and math.clamp(-hv.yr * math.abs(st.speed) * 0.012, -0.07, 0.07) or 0
      local pitch = hv and math.clamp((hv.af or 0) * 0.0025, -0.04, 0.04) or 0
      return CFrame.lookAt(p, p + face) * CFrame.Angles(pitch + math.sin(t * 0.8) * 0.01, 0, roll + math.sin(t * 1.0) * 0.015)
    end
    -- 两栖车：浮着时车底在吃水线（海面下大半个车体）；水浅到履带碰着海底，就踩着海底往上爬（车底取海底和吃水线高的那个），
    --   不会在水深 1.5 格那一下从吃水线弹到海面上
    local draft = d.amphib and d.hullH * 0.55 or nil
    -- 公式的高度；真地形和公式差多少由下面的 terrainLift（B 的，平滑过）整车补上——这里再照真地形量就补了两遍（E 11-24 合并时去掉）
    local function gh(p)
      if draft then return math.max(Map.height(p.X, p.Z), -draft) end
      return Map.ground(p.X, p.Z)
    end
    local c = V(pos.X, 0, pos.Z)
    local f, b = c + face * d.L * 0.4, c - face * d.L * 0.4
    local l, r = c - right * d.W * 0.4, c + right * d.W * 0.4
    local yf, yb, yl, yr = gh(f), gh(b), gh(l), gh(r)
    if draft and math.max(yf, yb, yl, yr) <= -draft + 1e-3 then   -- 四个角都够不着海底：浮着，随浪轻轻晃
      local t = os.clock()
      local cf = CFrame.lookAt(V(c.X, -draft + math.sin(t * 1.3) * 0.15, c.Z), V(c.X, -draft, c.Z) + face)
      return cf * CFrame.Angles(math.sin(t * 0.9) * 0.012, 0, math.sin(t * 1.1) * 0.02)
    end
    local y = (yf + yb + yl + yr) / 4
    -- 四个角定的平面在山脊、坡顶上会切进地里（中间的地比四角的平均高）：车底下再取 9 个点，哪儿冒出平面就整车抬起来
    --   只管整辆在陆地上的时候（水边、两栖车爬岸时四个角一半在水里，抬起来会一跳一跳）
    if math.min(yf, yb, yl, yr) > 0.3 then
      local gf, gr = (yf - yb) / (d.L * 0.8), (yr - yl) / (d.W * 0.8)
      local lift = 0
      for _, u in ipairs({ -0.45, 0, 0.45 }) do
        for _, s in ipairs({ -0.45, 0, 0.45 }) do
          local p = c + face * (u * d.L) + right * (s * d.W)
          local over = gh(p) - (y + gf * u * d.L + gr * s * d.W)
          if over > lift then lift = over end
        end
      end
      if lift > 0.2 then y += math.min(lift - 0.2, 4) end
    end
    if st and st.tLift then y += st.tLift end   -- 真地形比算的高度高 / 低多少（terrainLift，平滑过的；baseAt 只给自己开的车用）
    local fwd = (V(f.X, yf, f.Z) - V(b.X, yb, b.Z)).Unit
    local side = (V(r.X, yr, r.Z) - V(l.X, yl, l.Z)).Unit
    local up = side:Cross(fwd).Unit
    return CFrame.fromMatrix(V(c.X, y, c.Z), side, up, -fwd)
  end

  -- 车底下真的地形在哪（用户 11-22：「无数个 AI 修了半天修不好，坦克半截身子卡在地里」）：车底五个点往下打射线（只打地形、不管水），
  --   真地面比 Map.height 平均高（低）多少就把车抬高（放低）多少——Roblox 地形网格器画出来的地面和算的高度对不上时，车照样落在看得见的地面上。
  --   服务器开服时已经按量出来的网格器对照表写地形（World.lua 的 calibrate），对上了这里就是 0；没对上、弹坑挖低了也跟着。
  --   打不着（地形还没复制过来、在水里）就当 0；最多抬 4 格、放 1.5 格。View.lua 给别人的车也用它
  local groundParams = RaycastParams.new()
  groundParams.FilterType = Enum.RaycastFilterType.Include
  groundParams.IgnoreWater = true
  local LIFT_PTS = { { 0, 0 }, { 0.35, 0 }, { -0.35, 0 }, { 0, 0.35 }, { 0, -0.35 } }
  local function terrainLift(d, pos, yaw)
    local T = workspace:FindFirstChildOfClass("Terrain")
    if not T then return nil end
    groundParams.FilterDescendantsInstances = { T }
    local face = V(-math.sin(yaw), 0, -math.cos(yaw))
    local right = V(-face.Z, 0, face.X)
    local sum, n = 0, 0
    for _, o in ipairs(LIFT_PTS) do
      local p = pos + face * (o[1] * d.L) + right * (o[2] * d.W)
      local h = Map.height(p.X, p.Z)
      if h > 0.5 then
        local r = workspace:Raycast(V(p.X, h + 8, p.Z), V(0, -16, 0), groundParams)
        if r then
          sum += r.Position.Y - h
          n += 1
        end
      end
    end
    if n < 3 then return nil end
    return math.clamp(sum / n, -1.5, 4)
  end
  G.terrainLift = terrainLift

  local treeBuf = {}   -- 撞树（Map.treesNear 的结果表，每帧重用）
  local mapParams = RaycastParams.new()
  mapParams.FilterType = Enum.RaycastFilterType.Include
  local camParams = RaycastParams.new()   -- 镜头别钻进山坡、房子（地形也算）
  camParams.FilterType = Enum.RaycastFilterType.Include

  -- 发动机声（开车的人自己听）：低沉的轰鸣（爆炸声起爆那一小段放慢循环、削掉高音）+ 涡轮 / 履带的呜呜声（风声循环），
  --   油门越大、开得越快音调越高、越响；坦克沉一点，轮式车尖一点
  local engine = nil
  -- 一次性的真录音（起动、熄火、加速）：放在 SoundService，播完自己删
  local function realOnce(key, vol, speed)
    local id, cfg = nil, nil
    if G.realSound then id, cfg = G.realSound(key) end
    if not id then return nil end
    local s = Instance.new("Sound")
    s.SoundId = id
    s.Volume = (cfg and cfg.vol or 1) * (vol or 1)
    s.PlaybackSpeed = speed or 1
    s.Parent = game:GetService("SoundService")
    s:Play()
    game:GetService("Debris"):AddItem(s, ((cfg and cfg.len) or 4) / (speed or 1) + 0.5)
    return s
  end
  local function engineStop()
    if engine then
      for _, snd in pairs(engine.s) do if snd then snd:Destroy() end end
      if engine.layered and not engine.layered.turb then realOnce("tankStop", 0.9) end   -- 柴油机熄火一声
      engine = nil
    end
  end
  local function engineStart(d)
    engineStop()
    if not G.makeSound then return end
    local SS = game:GetService("SoundService")
    local heavy = d.arch ~= "wheeled"
    local realEng = heavy and G.realLoop and G.realLoop("tankEngine", SS)   -- 真录音的坦克发动机（SoundLib；没载上照旧叠出来的）
    local rumble = realEng or G.makeSound({ id = "rbxasset://sounds/impact_explosion_03.mp3", vol = 0.45, s = { 0.3, 0.3 }, loop = { 0.06, 0.5 }, eq = { 8, -2, -14 } }, SS, {})
    -- 涡轮呜呜声（Roblox 自带「下坠呼啸」改调出来的）：有真录音时不要（用户 11-22：坦克移动声音很奇怪——卡通味的呼啸叠在真发动机上）
    local whine = (not realEng) and G.makeSound({ id = "rbxasset://sounds/action_falling.ogg", vol = 1.5, s = { 0.7, 0.7 }, loop = { 1, 9 }, eq = { -8, 6, heavy and -2 or 3 } }, SS, {}) or nil
    -- 履带的哗啦声（用户 11-20：载具照 UE5 的水平升级）：咔哒那一下截一小段循环，开得越快一圈越短、越密；
    --   轮胎侧滑的沙沙声：风声削掉低音，侧滑越厉害越响
    local clank = heavy and G.makeSound({ id = "rbxasset://sounds/volume_slider.ogg", vol = 0, s = { 1, 1 }, loop = { 0, 0.07 }, eq = { 6, 2, -6 } }, SS, {}) or nil
    local skid = G.makeSound({ id = "rbxasset://sounds/action_falling.ogg", vol = 0, s = { 1.6, 1.6 }, loop = { 2, 6 }, eq = { -14, 4, 6 } }, SS, {})
    engine = { s = { rumble, whine, clank, skid }, rumble = rumble, whine = whine, clank = clank, skid = skid, heavy = heavy, rpm = 0.2, realEng = realEng ~= nil }
    -- 战雷式分层（用户 11-24：「坦克的发动机声音、加速声音」）：有行驶循环的录音就分层——
    --   柴油机：怠速层（转速低为主）和行驶层（转速上去、负载大更响更沉）交叉淡入淡出，上车先一声起动、下车一声熄火，猛踩油门叠一声加速；
    --   M1 系列（AGT1500 燃气轮机）：喷气发动机录音放慢当轰鸣、1000 赫兹纯音升调当尖啸，上车 2.5 秒从低转速爬上来，底下垫一层放慢的行驶录音；
    --   履带：真录音循环，车速越快越密越响；车里 / 镜里每层削掉高音（闷）
    if realEng and G.realLoop then
      local drive = G.realLoop("tankDrive", SS)
      if drive then
        local turb = d.turbine == true   -- 燃气轮机（VehDefs 的 turbine，A 挑的刺：原来写死 m1a1 / m1a2，以后加 T-80 照样认）
        local jet = turb and G.realLoop("jetEngine", SS) or nil
        local tone = (turb and jet) and G.realLoop("toneSine", SS) or nil
        local tracks = G.realLoop("tankTracks", SS)
        local L = { drive = drive, jet = jet, tone = tone, tracks = tracks, turb = turb and jet ~= nil and tone ~= nil, load = 0, t0 = os.clock() }
        for _, snd in pairs({ realEng, drive, jet, tone, tracks }) do
          snd.Volume = 0
          local e = Instance.new("EqualizerSoundEffect")
          e.Name = "Muffle"
          e.Parent = snd
          table.insert(engine.s, snd)
        end
        if not L.turb then
          if jet then jet:Destroy() L.jet = nil end
          if tone then tone:Destroy() L.tone = nil end
          realOnce("tankStart", 0.85)
        end
        engine.layered = L
      end
    end
  end
  -- 变速箱（用户：坦克驾驶参考战雷）：前进 5 档、倒挡 1 档；每档里转速随车速往上走，到顶换上一档、转速掉下来（听得出一档一档换），
  --   换挡那一下动力断一下（声音一沉）；st.gearN 给仪表显示档位
  local GEARS = 5
  local function engineStep(dt, thr, spd)
    if not engine then return end
    local back = st and (st.speed or 0) < -0.4
    local g = 0
    local want, shifting
    local GB = st and st.gb
    if GB then   -- 实际的变速箱（physics 里那套）：档位、转速、离合断开都照它
      g = GB.g
      st.gearN = g
      shifting = GB.cut > 0
      want = (g == 0) and (0.2 + 0.16 * math.abs(thr)) or math.clamp(0.16 + 0.84 * GB.rpm * (thr ~= 0 and 1 or 0.82), 0, 1)
      if shifting then want = math.min(want, 0.18 + 0.6 * GB.rpm) end
    else
      if spd > 0.02 then g = back and -1 or math.min(GEARS, math.floor(spd * GEARS * 0.98) + 1) end
      if st then
        if st.gearN ~= g and g > (st.gearN or 0) and g > 1 then   -- 升档：动力断一下、咔哒一声
          engine.shiftT = os.clock()
          if G.sfx then G.sfx("gearShift", nil, { vol = engine.heavy and 1 or 0.7 }) end
        end
        st.gearN = g
      end
      local inGear = (g >= 1) and (spd * GEARS - (g - 1)) or spd * 2
      want = math.clamp(0.22 + 0.6 * math.clamp(inGear, 0, 1) * (0.55 + 0.45 * math.abs(thr)) + 0.18 * math.abs(thr), 0, 1)
      shifting = os.clock() - (engine.shiftT or -9) < 0.25
      if shifting then want *= 0.75 end
    end
    engine.rpm += (want - engine.rpm) * math.min(1, dt * (shifting and 9 or 3.5))
    local r = engine.rpm
    local L = engine.layered
    if L then
      local function smooth(a, b, x)
        local k = math.clamp((x - a) / (b - a), 0, 1)
        return k * k * (3 - 2 * k)
      end
      -- 负载：踩着油门、车还没跑起来（加速中）大；松油门、匀速小——大负载更响、音色更沉
      local want2 = math.abs(thr) * math.clamp(1 - spd * 0.85, 0.15, 1)
      L.load += (want2 - L.load) * math.min(1, dt * 4)
      local load = L.load
      local now = os.clock()
      if L.turb then
        local spool = math.clamp((now - L.t0) / 2.5, 0, 1)   -- 起动：转速从低往上爬
        local rr = r * spool
        L.jet.PlaybackSpeed = 0.30 + 0.22 * spool + rr * 0.42 + load * 0.05
        L.jet.Volume = (0.30 + 0.45 * rr + 0.25 * load) * (0.4 + 0.6 * spool)
        L.tone.PlaybackSpeed = 1.35 + rr * 1.35 + load * 0.08   -- 尖啸 1350～2800 赫兹
        L.tone.Volume = (0.018 + 0.03 * rr + 0.02 * load) * spool
        engine.rumble.Volume = 0
        L.drive.PlaybackSpeed = 0.55 + r * 0.25
        L.drive.Volume = (0.12 + 0.25 * r) * smooth(0.02, 0.2, spd + load * 0.3)
      else
        local fadeIn = math.clamp((now - L.t0 - 1.1) / 1.0, 0, 1)   -- 起动声放完才进怠速
        local idleW = 1 - smooth(0.25, 0.62, r)
        engine.rumble.PlaybackSpeed = 0.9 + r * 0.35
        engine.rumble.Volume = (0.25 + 0.55 * idleW) * (0.35 + 0.65 * fadeIn)
        L.drive.PlaybackSpeed = 0.72 + r * 0.52 + load * 0.04
        L.drive.Volume = (smooth(0.12, 0.5, r) * (0.45 + 0.55 * load) + 0.12 * r) * 1.15 * fadeIn
        -- 猛踩油门（起步、刹停再走）：叠一声加速（3 秒内不重复）
        if math.abs(thr) > 0.7 and (L.prevThr or 0) < 0.35 and now - (L.accT or -9) > 3 and fadeIn >= 1 then
          L.accT = now
          realOnce("tankAccel", 0.75 + 0.25 * (1 - spd))
        end
      end
      L.prevThr = math.abs(thr)
      local airL = st and st.airS ~= nil
      if L.tracks then
        L.tracks.PlaybackSpeed = 0.55 + spd * 0.75
        L.tracks.Volume = airL and 0 or smooth(0.01, 0.18, spd) * (0.25 + 0.5 * spd)
      end
      if engine.clank then engine.clank.Volume = 0 end
      -- 车里 / 镜里：闷（削高音、低音厚一点）
      local inside = (st and st.sight) or (G.interiorOn and G.interiorOn())
      for _, snd in pairs({ engine.rumble, L.drive, L.jet, L.tone, L.tracks }) do
        local e = snd and snd:FindFirstChild("Muffle")
        if e then e.LowGain, e.MidGain, e.HighGain = inside and 3 or 0, inside and -4 or 0, inside and -16 or 0 end
      end
      local slip = (st and not airL) and math.abs(math.sin(st.slipA or 0)) * math.clamp(math.abs(st.speed or 0) / 20, 0, 1) or 0
      engine.skid.Volume = math.clamp((slip - 0.08) * 9, 0, 2.2)
      engine.skid.PlaybackSpeed = 1.4 + slip * 1.2
      return
    end
    if engine.realEng then   -- 真录音：转速高了放快一点、响一点；叠出来的涡轮尖啸压低（别盖住真录音）
      engine.rumble.PlaybackSpeed = 0.8 + r * 0.55
      engine.rumble.Volume = 0.5 + 0.6 * r
    else
      engine.rumble.PlaybackSpeed = (engine.heavy and 0.24 or 0.32) + r * (engine.heavy and 0.22 or 0.32)
      engine.rumble.Volume = 0.3 + 0.35 * r
    end
    if engine.whine then
      engine.whine.PlaybackSpeed = (engine.heavy and 0.5 or 0.65) + r * 0.6
      engine.whine.Volume = 0.6 + 2.6 * r * r
    end
    local air = st and st.airS ~= nil
    if engine.clank then   -- 履带：速度越快越密；在天上没有
      -- 原来 0.55～2.15 倍速：一秒三十来下、连成一片电子嗡嗡声；放慢、放轻，听得出一节节的咔哒（有真录音时再轻一点）
      engine.clank.PlaybackSpeed = 0.35 + spd * 0.8
      engine.clank.Volume = (air or spd < 0.02) and 0 or math.min(0.5, 0.1 + spd * 0.45) * (engine.realEng and 0.6 or 1)
    end
    local slip = (st and not air) and math.abs(math.sin(st.slipA or 0)) * math.clamp(math.abs(st.speed or 0) / 20, 0, 1) or 0
    engine.skid.Volume = math.clamp((slip - 0.08) * 9, 0, 2.2)
    engine.skid.PlaybackSpeed = 1.4 + slip * 1.2
  end
  local aimParams = RaycastParams.new()
  aimParams.FilterType = Enum.RaycastFilterType.Exclude

  -- 进出瞄准镜、换光电模式、放烟幕：键盘、手机按钮共用
  -- 车长望远镜（用户 11-27「再做一个望远镜」）：C 开关；开着时 Shift / 右键直接进炮长瞄准镜
  local function setBinoc(on)
    on = on and true or false
    if not st or (st.binoc == true) == on then return end
    if on and st.arty and G.artyOff then G.artyOff() st.arty = false end
    st.binoc = on
    GS.binoShow(on, st.kit)
    if G.sfx then pcall(G.sfx, "uiClick") end
  end
  local function setSight(on)
    if not st or st.sight == on then return end
    if on and st.binoc then setBinoc(false) end
    st.sight = on
    GS.reset()
    ownVisible(not on)
    applyMode()
  end
  G.driveBinoc = function(on)   -- 手机按钮、测试：不给参数就切换；返回现在开没开
    if not st then return false end
    if on == nil then on = not st.binoc end
    if on and st.sight then setSight(false) end
    setBinoc(on)
    return st.binoc == true
  end
  -- 开镜 / 退镜：坐在车里炮长位上时先把头凑到目镜上 / 从目镜上抬起来（Interior.lua 演完再真的切），
  --   不管在哪都有目镜的光学效果（先黑，亮圆从边上滑进来、变大）——用户 11-21：看倍镜会有的效果
  G.driveSetSight = function(on) setSight(on) applyMode() end   -- Interior.lua：辅助瞄准镜也要炮跟着鼠标瞄
  local function toggleSight()
    if not st then return end
    if st.binoc then setBinoc(false) end   -- 望远镜里按 Shift / 右键：收起望远镜、进炮长瞄准镜
    -- 曲射（自行火炮、火箭炮的 arty）：Shift 进 / 出炮兵视角（ArtyView.lua，坦克世界那样从天上看、挪瞄准点）
    if G.artyToggle and (G.artyOn and G.artyOn() or (G.artyWeapon and G.artyWeapon(st))) then
      st.arty = G.artyToggle(st) == true
      return
    end
    local want = not st.sight
    -- 全真模式（战雷）：不能退回第三人称——有车内就坐进车里再退镜，没有就留在瞄准镜里
    if not want and workspace:GetAttribute("WtMode") == "sb" and not (G.interiorOn and G.interiorOn()) and not (G.inTestDrive and G.inTestDrive()) then   -- 试驾不强制第一人称
      if not (G.interiorEnterSeat and G.interiorEnterSeat()) then return end
    end
    if G.interiorScope and G.interiorScope(want, function() setSight(want) end) then return end
    setSight(want)
  end
  G.driveToggleSight = function() toggleSight() end   -- 测试用：同按 Shift（曲射武器进炮兵视角）
  -- 瞄准镜默认档（用户 11-21：坦克开镜强制锁在夜视；11-22：「坦克第一人称视角开镜有时候会是绿色的」）：天黑热成像（白热，现代坦克夜里就用这个）、
  --   白天昼光；自己换过就记住（白天、夜里各记一个）
  G.sightPref = G.sightPref or {}
  local function nightNow() return G.isNight ~= nil and G.isNight() end
  local function nextMode()
    if not st then return end
    local allow = st.allow or { 1, 2, 3, 4 }
    local i0 = table.find(allow, st.mode) or 0
    st.mode = allow[i0 % #allow + 1]
    G.sightPref[nightNow() and "night" or "day"] = st.mode
    applyMode()
  end
  G.sightReapply = function() applyMode() end   -- WtVfx.lua：观瞄打坏 / 修好时重新套光电模式
  local function smoke() G.R.Drive:FireServer({ op = "smoke" }) end

  local function begin(vs)
    local em = findEnt(vs.id)
    if not em then return end
    local d = VD.get(vs.m)
    if not d then return end
    d = TMods.applyDef(d, em:GetAttribute("Mods"))   -- 坦克改装（TankMods）：车速、武器表（加特林是第 3 件）按选的改一份
    local root = em.Root.CFrame
    local base = root * CF(0, -d.H / 2, 0)
    local look = base.LookVector
    local yaw = math.atan2(-look.X, -look.Z)
    st = { id = vs.id, em = em, d = d, pos = base.Position, yaw = yaw, speed = 0, steer = 0, accel = 0, root = root,
      ty = em:GetAttribute("Ty") or 0, gp = em:GetAttribute("Gp") or 0, camYaw = yaw, camPitch = -0.12, sight = false,
      mode = 1, zoom = 1,
      wi = 1, sendT = 0, next = {}, firing = false, hlT = 0, my = em:GetAttribute("My") or 0, mp = em:GetAttribute("Mp") or 0,
      fcs = { am = nil, R = nil, laseT = nil, ry = 0, rp = 0,   -- 火控：弹种、测的距离（米）、测距的时刻、瞄准线跟踪的角速度
        lrf = "LAST", arm = true, multi = false,   -- 激光：末回波 / 首回波（真车开机默认末回波）、待命 / 保险、上一次是不是多回波
        mode = 1,                                  -- 火控方式：1 正常、2 应急（没有提前量）、3 手动（没有弹道计算机、没有稳定、手摇方向高低机）
        bsR = {},                                  -- 各弹种的战斗瞄准距离（调整页改过的；没改是弹种自己的）
        droop = 0, mrs = 0,                        -- 炮管热弯曲（毫弧度：开炮炮管发热往下弯，慢慢冷回来）、上次炮口基准更新时量的弯曲
        bore = { 0, 0 } },                         -- 校炮偏差（密位：方向、高低）
      -- 科技树的火控（WtMods.FCS，服务器出车时写 FcsGen / ModFcs）：测距多久、误差、解算多久、提前量、残余散布、自动跟踪；
      --   没写（沙盒、老模式的车）按原来那样：有激光就马上测、测距那一下算提前量
      fcsP = em:GetAttribute("FcsGen") and WM.fcsParams(em:GetAttribute("FcsGen"), em:GetAttribute("ModFcs") or 0) or nil,
      stab = not d.noStab, retLvl = 0, symLvl = 0, retNight = false, thGain = 2, thLevel = 2 }   -- 稳定器（VehDefs 的 noStab：M60 没有稳定器，开局就是关的）、分划亮度、符号亮度、分划夜间照明、热像增益、电平
    -- 观瞄按年代（WtOptics，用户 11-26）：这辆车有哪几种光电通道、夜视是哪一种、分划是哪一套；
    --   默认档：记着的（这辆车有才用）→ 天黑用这辆车最好的夜视（热像 > 微光 > 主动红外）→ 昼光
    do
      local tk = em:GetAttribute("TreeKey")
      local itT = (tk and TTr.get(tk)) or (TTr.byVeh and TTr.byVeh[d.id])   -- 沙盒、电脑车没有 TreeKey：按型号找科技树里那一项的年代、国家
      local fg = em:GetAttribute("FcsGen")
      if fg == nil and itT then fg = WM.fcsGen(itT) end   -- 同服务器出车时的算法（年代、有没有激光、是不是坦克）
      st.kit = OPT.kit(tk or (itT and itT.key), d.id, fg, itT and itT.year, itT and itT.nat)
      if (em:GetAttribute("ModFcs") or 0) >= 3 and (fg or 0) >= 3 then st.kit.ret = "hk" end   -- 火控升满：数字火控加自动跟踪
      st.allow = st.kit.modes
      local pref = G.sightPref[nightNow() and "night" or "day"]
      if pref and table.find(st.allow, pref) then
        st.mode = pref
      elseif nightNow() then
        st.mode = table.find(st.allow, 3) and 3 or (table.find(st.allow, 2) and 2 or (table.find(st.allow, 5) and 5 or 1))
      end
    end
    G.drive, G.myVeh = st, st
    -- 炮兵视角（ArtyView.lua）用：炮口在哪（画弹道弧线）、当前武器还要装填几秒
    st.muzzle = function()
      local base = st.root * CF(0, -d.H / 2, 0)
      return VD.muzzle(d, base, st.ty, st.gp, nil, st.my, st.mp).Position
    end
    st.reloadLeft = function()
      local wid = d.weapons[st.wi]
      return wid and math.max(0, (st.next[wid] or 0) - os.clock()) or 0
    end
    -- Shift 进出瞄准镜：高优先级绑定，吃掉这一下（不然 Roblox 自带的 Shift 锁定视角也会动）
    CAS:BindActionAtPriority("DriveSight", function(_, state)
      if state == Enum.UserInputState.Begin and st then toggleSight() end
      return Enum.ContextActionResult.Sink
    end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
    cam.CameraType = Enum.CameraType.Scriptable
    panel.Visible = not G.vehHudOn   -- 有新的驾驶界面（VehHud.lua）就不画这块小面板、圆圈、黄十字
    cross.Visible = not G.vehHudOn
    gunMark.Visible = not G.vehHudOn
    if G.touchDriveUI then for _, f in ipairs(G.touchDriveUI) do f.Visible = true end end
    local m = workspace:FindFirstChild("Map")
    mapParams.FilterDescendantsInstances = m and { m } or {}
    camParams.FilterDescendantsInstances = m and { m, workspace.Terrain } or { workspace.Terrain }
    if G.playSound then G.playSound("capture") end
    engineStart(d)
  end

  local function stop()
    if st then
      if G.artyOff then G.artyOff() end
      st.arty = false
      ownVisible(true)
      st.binoc = false
      GS.binoShow(false)
      st.sight = false
      applyMode()
      local m = ownModel()
      if m and m.Parent == ownBox and G.viewFolder then m.Parent = G.viewFolder end
    end
    st = nil
    engineStop()
    if G.vehCamReset then G.vehCamReset("drive") end
    G.drive, G.myVeh = nil, nil
    CAS:UnbindAction("DriveSight")
    cam.CameraType = Enum.CameraType.Custom
    cam.FieldOfView = 70
    if UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then UIS.MouseBehavior = Enum.MouseBehavior.Default end
    panel.Visible, cross.Visible, gunMark.Visible = false, false, false
    if G.touchDriveUI then for _, f in ipairs(G.touchDriveUI) do f.Visible = false end end
  end

  local function approach(a, b, s)
    if a < b then return math.min(b, a + s) end
    return math.max(b, a - s)
  end
  local function angDiff(a, b) return (b - a + 180) % 360 - 180 end

  -- 坐在气垫艇上（登陆平台出发）：开的是艇，不是车（用户：登陆的时候我应该驾驶登陆船，而不是让坦克带着登陆船）——
  --   气垫艇的手感：推力沿艇首（风扇在艇尾），前后、侧向的阻力分开算（侧向也小：转弯时甩尾、横着滑一段）；
  --   舵在风扇后面，越快越灵，低速靠首部喷口慢慢转；转向有惯性；车停在甲板上不动（炮塔照样能转、能打）。
  --   能冲上平缓的沙滩；车底下是陆地了服务器就把车放下（Armor.lua dropOff），接着开车从艇首开下去
  local function hover(dt, thr, str)
    local d, L = st.d, VD.LCAC
    local fwd = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
    local hv = st.hv
    if not hv then
      hv = { v = fwd * st.speed, yr = 0, af = 0 }
      st.hv = hv
    end
    local right = V(-fwd.Z, 0, fwd.X)
    local v = hv.v
    local vf, vs = v:Dot(fwd), v:Dot(right)
    local push = (thr > 0) and 22 or ((thr < 0) and -10 or 0)   -- 格 / 秒²：推满大约 75 格 / 秒到顶（VehDefs.LCAC.speed）
    local af = push - vf * 0.22 - vf * math.abs(vf) * 0.001
    local as = -vs * 0.9 - vs * math.abs(vs) * 0.004
    -- 艇首前面是陡坡、堤岸：冲不上去（平缓的沙滩能上）
    local bow = st.pos + fwd * (L.size.Z * 0.5)
    local hb, hc = Map.height(bow.X, bow.Z), Map.height(st.pos.X, st.pos.Z)
    if vf > 0 and hb > math.max(hc, 0) + 3 then af = math.min(af, -vf * 4) end
    v += (fwd * af + right * as) * dt
    local auth = 0.3 + 0.7 * math.clamp(math.abs(vf) / 35, 0, 1)
    local yrWant = -str * math.rad(24) * auth * ((vf < -1) and -1 or 1)
    hv.yr += (yrWant - hv.yr) * math.min(1, dt * 1.4)
    st.yaw += hv.yr * dt
    -- 撞上登陆平台、码头、舰船：弹回来一点
    local np = st.pos + v * dt
    local sp = v.Magnitude
    if sp * dt > 1e-3 then
      local o = V(st.pos.X, math.max(hc, 0) + L.deck + 2, st.pos.Z)
      local res = workspace:Raycast(o, v.Unit * (L.size.Z * 0.5 + sp * dt + 1), mapParams)
      if res then
        if sp > 20 and G.shake then G.shake(0.3) end
        v = -v * 0.25
        np = st.pos
      end
    end
    hv.v, hv.af = v, af
    st.pos = V(np.X, st.pos.Y, np.Z)
    st.speed = v:Dot(fwd)
    st.accel = af
    st.steer = approach(st.steer, str, dt * 4)
    local base = baseAt(d, st.pos, st.yaw, true)
    st.pos = base.Position
    st.root = base * CF(0, d.H / 2, 0)
  end
  -- 气垫艇在自己车底下的样子（View 用：自己开的那条艇按本地算的位置画，跟车贴得死死的；同服务器 Armor.lua 的 lcacUnder，艇比车靠前 2 格）
  function G.lcacUnderMine(cid)
    if not st or st.id ~= cid or not st.hv or not st.root then return nil end
    local L = VD.LCAC
    return st.root * CF(0, -st.d.H / 2, 0) * CF(0, L.y - L.deck, -2)
  end

  -- 路面（用户 11-20：所有载具操控照虚幻引擎 5 的水平升级）：每 0.25 秒看一次脚下——土路硬、快；草地正常；沙地软（慢、打滑，轮式车更明显）；
  --   石头地颠、抓地差一点。rough 给镜头的颠簸、grip 给侧滑（Map.material 跟扬尘、小地图用的是同一套）
  local SURF = {
    [Enum.Material.Ground] = { speed = 1.06, accel = 1.05, grip = 1.0, rough = 0.55 },
    [Enum.Material.Grass] = { speed = 1.0, accel = 1.0, grip = 0.92, rough = 0.75 },
    [Enum.Material.LeafyGrass] = { speed = 0.98, accel = 0.98, grip = 0.9, rough = 0.8 },
    [Enum.Material.Sand] = { speed = 0.82, accel = 0.76, grip = 0.72, rough = 0.5 },
    [Enum.Material.Rock] = { speed = 0.9, accel = 0.92, grip = 0.86, rough = 1.5 },
    [Enum.Material.Slate] = { speed = 0.9, accel = 0.92, grip = 0.86, rough = 1.5 },
    [Enum.Material.Concrete] = { speed = 1.1, accel = 1.08, grip = 1.04, rough = 0.3 },   -- 港口的码头平地、坡道
    [Enum.Material.Asphalt] = { speed = 1.1, accel = 1.08, grip = 1.06, rough = 0.25 },
  }
  -- 雪、冰（用户 11-26 夜「坦克要能滑雪」）：雪地抓地差一截，冰面（河、湖的冰）更滑——起步、刹车使不上劲，转弯甩尾，
  --   坡上往下滑（下面 slide）；mu 是溜坡的摩擦系数（车停着刹住时，坡的下滑力超过 mu × 压力就往下溜；履带横着更不容易滑）
  SURF[Enum.Material.Snow] = { speed = 0.93, accel = 0.86, grip = 0.6, rough = 0.42, mu = 0.42 }
  SURF[Enum.Material.Glacier] = { speed = 0.97, accel = 0.62, grip = 0.24, rough = 0.12, mu = 0.12 }
  SURF[Enum.Material.Ice] = { speed = 0.97, accel = 0.6, grip = 0.22, rough = 0.12, mu = 0.11 }
  -- 雪山图的路（地形底下是 Ground：压实的雪路）：比雪地抓得住，比干土路滑
  local SURF_SNOWROAD = { speed = 1.04, accel = 1.0, grip = 0.8, rough = 0.4, mu = 0.55 }
  local SURF0 = { speed = 1, accel = 1, grip = 0.9, rough = 0.7 }
  G.driveSurf = SURF   -- 测试用
  local SURF_WATER = { speed = 1, accel = 1, grip = 0.55, rough = 0.25 }
  local function surfAt(p)
    local h = Map.height(p.X, p.Z)
    if h < -1.5 then return SURF_WATER end
    local m = Map.material(p.X, p.Z, h, Map.slope(p.X, p.Z))
    if Map.SNOW and m == Enum.Material.Ground then return SURF_SNOWROAD end
    return SURF[m] or SURF0
  end
  local GRAV = 9.81 * 2.8 * 1.15   -- 重力（格 / 秒²；1 米 = 2.8 格，稍微沉一点：几十吨的车落得干脆）
  local function angR(a, b) return (b - a + math.pi) % (2 * math.pi) - math.pi end   -- a 到 b 转多少（弧度，-π～π）
  -- 落地：按砸下来的速度——镜头一沉、震屏、一声闷响、车两边扬起一团土、车头往下一点
  local function land(imp)
    if imp < 6 then return end
    local k = math.clamp((imp - 6) / 30, 0, 1)
    if G.shake then G.shake(0.12 + 0.5 * k) end
    if G.sfx then G.sfx("vehLand", nil, { vol = 0.45 + 0.9 * k }) end
    local v = G.views and G.views[st.em]
    if v and v.M and v.M.dust then
      for _, pe in ipairs(v.M.dust) do pcall(function() pe:Emit(math.floor(5 + 16 * k)) end) end
    end
    if st.sus then st.sus.vp -= 0.5 * k end
    st.landK = k   -- 测试用
    st.landT = os.clock()
  end
  -- 撞上东西（房子、工事、陡坎）：按撞的速度和正不正——震屏、一声撞击（擦着墙走只响第一下）
  local function bump(strength)
    local t = os.clock()
    if t - (st.bumpT or -9) < 0.45 or strength < 5 then return end
    st.bumpT = t
    local k = math.clamp(strength / 45, 0, 1)
    if G.shake then G.shake(0.1 + 0.5 * k) end
    if G.sfx then G.sfx("vehHit", nil, { vol = 0.4 + 0.9 * k }) end
  end

  local function physics(dt)
    local d = st.d
    local key = function(k) return UIS:IsKeyDown(k) end
    local thr = (key(Enum.KeyCode.W) and 1 or 0) - (key(Enum.KeyCode.S) and 1 or 0)
    local str = (key(Enum.KeyCode.D) and 1 or 0) - (key(Enum.KeyCode.A) and 1 or 0)
    if G.touchDrive then
      if G.touchDrive.thr ~= 0 then thr = G.touchDrive.thr end
      if G.touchDrive.str ~= 0 then str = G.touchDrive.str end
    end
    if G.interiorEngineOff then thr = 0 end   -- 驾驶员显示器上按了熄火（Interior.lua）：再按起动才走得了
    if st.em and st.em:GetAttribute("WtMob") == false then thr, str = 0, 0 end   -- 战雷式伤害（服务器 Wt.lua）：驾驶员没了、发动机 / 传动 / 履带坏了
    local inWater = Map.height(st.pos.X, st.pos.Z) < -1.5
    local carried = st.em ~= nil and st.em:GetAttribute("Lcac") == true   -- 站在气垫艇上（登陆平台出发、不会游的车）：开的是艇
    if carried then
      hover(dt, thr, str)
      return
    end
    if st.hv then   -- 刚被放下艇：车底从甲板落到地面，0.6 秒滑下去（不一下子掉），带着一点艇的速度
      local fwd0 = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
      st.speed = math.clamp(st.hv.v:Dot(fwd0) * 0.3, 0, d.speed)
      st.dropFrom, st.dropT, st.dropAt = st.root and (st.root * CF(0, -d.H / 2, 0)).Position.Y, 0, st.pos
      st.hv = nil
    end
    -- 科技树改装（WtMods，服务器出车时写的 ModSpd / ModAcc / ModTurn）：发动机、传动、空滤、悬挂、履带
    local em0 = st.em
    local mSpd, mAcc, mTurn = (em0 and em0:GetAttribute("ModSpd")) or 1, (em0 and em0:GetAttribute("ModAcc")) or 1, (em0 and em0:GetAttribute("ModTurn")) or 1
    local maxF, maxR = d.speed * mSpd, d.rev * mSpd
    -- 扫雷犁放着（或正在升）：车速不超过 15 公里 / 时（Pearson 全宽扫雷犁犁地 1–15 公里 / 时；按这型车真车公路速度的比例换成游戏车速）
    local plowA = st.em and st.em:GetAttribute("Plow")
    if plowA and plowA > 0 then
      local sp = TMods.SPEC[d.id]
      maxF = math.min(maxF, d.speed * TMods.KIT.plow.vcap / ((sp and sp.vmax) or 65))
    end
    if inWater then
      if carried then maxF, maxR = VD.LCAC.speed, 12 else maxF, maxR = d.speed * 0.32, d.rev * 0.3 end
    end
    -- 路面：极速、加速、抓地（履带车在软地上吃亏少一些）
    local tracked = d.arch ~= "wheeled"
    st.surfT = (st.surfT or 0) - dt
    if st.surfT <= 0 or not st.surf then st.surfT, st.surf = 0.25, surfAt(st.pos) end
    local sf = st.surf
    local kS = tracked and (1 - (1 - sf.speed) * 0.55) or sf.speed
    local kA = tracked and (1 - (1 - sf.accel) * 0.6) or sf.accel
    if not inWater then maxF, maxR = maxF * kS, maxR * kS end
    local accel = d.accel * (inWater and 1 or kA) * mAcc
    -- 驾驶手感（用户：驾驶手感也做到最好）：
    --   油门——发动机低速劲大、接近极速劲小；反着推是刹车（比加速猛得多）；松油门滚着慢下来（履带阻力大停得快）；
    --   上坡掉速、下坡溜得快（按车身俯仰）；停稳了松油门不溜车（手刹）
    local v = st.speed
    local slope = inWater and 0 or (st.slopeS or 0)
    -- 变速箱（用户 11-25 晚「那你做战雷手感吧」）：前进几档、倒挡一两档，每档管一段车速，档里有转速——
    --   转速中段劲最足、快到顶劲小了（得换档）；到顶升档：离合断开 0.3～0.45 秒（没了动力、车身往前一点头、转速掉下来），
    --   接上下一档再往前一拱；慢下来自动降档；停住松油门挂空档。车的真极速、整体加速快慢照旧（乘在原来那条曲线上）
    local GB = st.gb
    if not GB then
      GB = { nf = (d.gears and d.gears[1]) or (tracked and 5 or 6), nr = (d.gears and d.gears[2]) or (tracked and 2 or 1),
        g = 0, cut = 0, rpm = 0.2, shiftT = tracked and 0.42 or 0.3 }
      st.gb = GB
    end
    local function bandTop(g)   -- 第 g 档（负的是倒挡）能开到多快：低档管的速度段短（11-26：0.8 → 0.72，一档管到 23 公里 / 时上下，
      --   起步不在 20 公里 / 时前头先断一下动力；配上下面的出力，豹 2A6 0–20 / 40 / 60 公里 / 时 1.7 / 6.7 / 16 秒，战雷 1.6 / 6.1 / 16）
      if g > 0 then return maxF * (g / GB.nf) ^ 0.72 end
      return maxR * (-g / GB.nr) ^ 0.72
    end
    local av = math.abs(v)
    if GB.cut > 0 then
      GB.cut -= dt
      if GB.cut <= 0 then GB.cut, GB.g = 0, GB.pend or GB.g end   -- 离合接上：下一档
    end
    if thr == 0 and av < 0.6 then
      GB.g, GB.cut = 0, 0   -- 停住、松油门：空档
    elseif thr ~= 0 and (GB.g == 0 or (GB.g > 0) ~= (thr > 0)) and (av < 1 or (thr > 0) == (v > 0)) then
      GB.g, GB.cut = (thr > 0) and 1 or -1, 0   -- 起步：挂一档 / 倒一档（停着才换向；开着反推是刹车）
    end
    local g = GB.g
    if g ~= 0 and GB.cut <= 0 then
      local n = (g > 0) and GB.nf or GB.nr
      local ga = math.abs(g)
      if ga < n and thr ~= 0 and (thr > 0) == (g > 0) and av >= bandTop(g) * 0.985 then   -- 到顶：升档
        GB.cut, GB.pend = GB.shiftT, g + ((g > 0) and 1 or -1)
        if G.sfx then G.sfx("gearShift", nil, { vol = tracked and 1 or 0.7 }) end
      elseif ga > 1 and av < bandTop(g - ((g > 0) and 1 or -1)) * 0.8 then   -- 慢下来：降档（不断动力）
        GB.g = g - ((g > 0) and 1 or -1)
        g = GB.g
      end
    end
    do   -- 转速：这一档速度段里走到哪了（离合断开时往下一档的转速掉）
      local gg = (GB.cut > 0 and GB.pend) or g
      local rpm = 0.2
      if gg ~= 0 then
        local top = bandTop(gg)
        local lo = (math.abs(gg) > 1) and bandTop(gg - ((gg > 0) and 1 or -1)) * 0.85 or 0
        rpm = 0.38 + 0.62 * math.clamp((av - lo) / math.max(top - lo, 0.1), 0, 1)
      end
      GB.rpm += (rpm - GB.rpm) * math.min(1, dt * ((GB.cut > 0) and 10 or 6))
    end
    st.rpmP, st.shifting = GB.rpm, GB.cut > 0
    local a
    if st.airS then   -- 在天上：没有抓地，只有一点空气阻力
      a = -v * 0.05
    elseif thr ~= 0 and (math.abs(v) < 1 or (thr > 0) == (v > 0)) then
      local vmax = (thr > 0) and maxF or maxR
      local av = math.abs(v)
      st.brkK = 0
      if GB.cut > 0 then
        a = -math.sign(v) * accel * 0.12   -- 离合断开：没有动力，只剩一点阻力（战雷换档那一下）
      else
        -- 战雷式出力（用户 11-26「坦克驾驶感跟战雷还是有差别」，查了战雷的数据：豹 2A6 0–20 公里 / 时 1.6 秒、0–40 6.1 秒、
        --   0–60 16 秒、到 68 要 22 秒——起步一脚就冲（约 0.4 g），越快越使不上劲，最后十几公里磨很久。原来正好反过来：
        --   起步 2.5 秒才到 20（肉），0–60 只要 10 秒（后段太快、没分量））：
        --   牵引 = min(起步上限 0.41 g × 抓地, 功率 ÷ 车速) − 滚动阻力 0.05 g；功率按 accel（≈ 0.22 × 马力 / 吨）折，传动效率 0.85：
        --   0.85 × 0.7457 ÷ 0.22 × 2.8² ≈ 22.6 × accel（格² / 秒³）；档里转速中段劲足一点（± 一成）；快到极速（最后 3%）调速器收油
        local tq = 0.9 + 0.2 * math.sin(math.pi * math.clamp(GB.rpm, 0, 1)) ^ 0.8
        local launch = 11.3 * math.clamp(sf.grip or 1, 0.15, 1.1)
        local pull = math.min(launch, 22.6 * accel * tq / math.max(av, 0.5))
        local gov = math.clamp((1 - av / math.max(vmax, 1)) / 0.03, 0, 1)
        local dir = (av > 0.05) and math.sign(v) or thr
        a = thr * pull * gov - dir * 1.37
        if av < 0.5 and a * thr < 0 then a = 0 end   -- 起步那一下推不动（顶着坡、陷在软地里）：不往后溜
      end
      if av > vmax then a = -math.sign(v) * accel * 0.7 end   -- 下坡冲过极速、开进软地：发动机拖住
    elseif thr ~= 0 then
      -- 刹车（反着推油门）：战雷约 0.5 g、0.1 秒多一点踩到底（原来按发动机 accel 的 3.2 倍——马力大的车刹得也猛，0.5～0.7 g 不等）
      st.brkK = math.min(1, (st.brkK or 0) + dt / 0.12)
      a = thr * 15.1 * math.clamp(sf.grip or 1, 0.15, 1.1) * st.brkK
    else
      st.brkK = 0
      -- 用户 11-25 晚「没有战雷那种纸片的脆感」：松油门履带车很快收住（原来 1.1 倍加速度，滑得肉）；
      --   雪、冰上收不了那么快（刹得住多少看地面摩擦：mu × 压力），陡坡上刹不住就往下溜
      local cosT = math.sqrt(math.max(0, 1 - slope * slope))
      local cap = math.min(accel * (tracked and 1.7 or 0.7), sf.mu and (18 * sf.mu * 1.1 * cosT) or math.huge)   -- 只有雪、冰、雪路给了 mu：别的图手感不变
      a = -math.sign(v) * math.min(math.abs(v) / math.max(dt, 1e-3), cap)
    end
    if not st.airS then
      if math.abs(v) > 0.5 or thr ~= 0 then a -= 18 * slope end   -- 上坡往后拉、下坡往前推（停着不溜）
      -- 停着、松油门也刹不住的坡（雪坡、冰坡：坡的下滑力 > mu × 压力）：带着刹死的履带往下溜（滑雪）
      if thr == 0 and math.abs(v) <= 0.5 and not inWater and sf.mu then   -- 只有雪、冰、雪路（给了 mu 的地面）会溜：别的图照旧停住不溜
        local mu = sf.mu
        local cosT = math.sqrt(math.max(0, 1 - slope * slope))
        if math.abs(slope) > mu * 1.15 * cosT then
          a = -18 * slope + math.sign(slope) * 18 * mu * 0.85 * cosT
          st.slideLon = true
        end
      end
      -- 履带车转弯吃速度：一侧离合 + 刹车（战雷现在的转向机构），高速打满一个 90° 掉 5～10 公里 / 时（原来 0.35，一个弯掉三十多公里 / 时）
      if tracked then a -= math.abs(st.yr or 0) * v * 0.14 end
    end
    -- 空格：刹车（战雷坦克的「急停」，比反着推油门停得还快；松开照常走）
    if not st.airS and key(Enum.KeyCode.Space) and G.hangarActive and G.hangarActive() then
      st.brkK = math.min(1, (st.brkK or 0) + dt / 0.1)
      a = -math.sign(v) * math.min(math.abs(v) / math.max(dt, 1e-3), 16.5 * math.clamp(sf.grip or 1, 0.15, 1.1) * st.brkK)
    end
    local old = v
    v += a * dt
    if thr == 0 and math.abs(v) < 0.4 and not st.slideLon then v = 0 end
    st.slideLon = nil
    v = math.clamp(v, -maxR * 1.25, maxF * 1.3)
    st.speed = v
    st.accel = (v - old) / math.max(dt, 1e-3)
    -- 转向有惯性：履带车原地能转、越快转得越慢（D 永远往右转车头）；轮式车前轮打角（越快打得越少、打过去要一会儿），
    --   按轴距算转弯半径（走起来才转，倒车反着），侧向抓地有上限（太快转不过来、推头）
    if st.airS then   -- 在天上转不了向：转速慢慢没了
      st.yr = approach(st.yr or 0, 0, math.rad(d.turn) * dt)
    elseif tracked then
      local k = 1 - 0.38 * math.clamp(math.abs(v) / math.max(maxF, 1), 0, 1)
      -- 车身转动有惯量（战雷：起转 0.4～0.6 秒）：起转 0.32 秒、收住 0.18 秒——比战雷利落一点（用户 11-25 要的脆感），
      --   原来 0.22 / 0.11 秒，几十吨的车身像没有重量
      -- 雪、冰上履带打滑：起转慢、收不住（车身转着往前甩一点）
      local gk = 0.35 + 0.65 * math.clamp(sf.grip or 1, 0, 1)
      st.yr = approach(st.yr or 0, str * math.rad(d.turn * mTurn) * k, math.rad(d.turn * mTurn) * ((str ~= 0) and 3.1 or 5.5) * gk * dt)
    else
      local frac = math.clamp(math.abs(v) / math.max(maxF, 1), 0, 1)
      st.steerA = approach(st.steerA or 0, str * math.rad(38 - 26 * frac), math.rad(75) * dt)
      local want = v / (d.L * 0.55) * math.tan(st.steerA)
      -- 抓地有上限（太快转不过来、推头）；转得猛的时候车头能比抓地多转一些——多出来的那份是甩尾（下面 travel 跟不上车头）
      local grip = 30 / math.max(math.abs(v), 1) * sf.grip
      st.yr = approach(st.yr or 0, math.clamp(want, -grip * 1.45, grip * 1.45), 4 * dt)
    end
    st.yaw -= st.yr * dt
    -- 车头朝向（yaw）和真正往哪走（travel）分开（UE5 的轮胎侧偏）：抓地有限，转得太猛、太快时车尾往外甩——
    --   轮式车明显，履带车只有高速急转才滑一点；滑着走掉速、扬尘、轮胎沙沙响；慢下来、停住就对齐
    st.travel = st.travel or st.yaw
    if math.abs(v) < 3 then
      st.travel = st.yaw
    elseif not st.airS then
      local gripRate = (tracked and 7.5 or 3.4) * sf.grip
      st.travel += angR(st.travel, st.yaw) * (1 - math.exp(-gripRate * dt))
    end
    st.slipA = angR(st.travel, st.yaw)
    if not st.airS and math.abs(v) > 3 then
      -- 侧滑掉速：冰上摩擦小，掉得少（一直往前滑）
      v -= v * math.min(1, math.abs(math.sin(st.slipA)) * 2.2 * (0.3 + 0.7 * math.clamp(sf.grip or 1, 0, 1)) * dt)
      st.speed = v
    end
    -- 横着往坡下滑（用户 11-26 夜「坦克要能滑雪」）：横坡的下滑力超过履带 / 轮胎横向能抓住的（mu × 压力；开着走的时候履带在动，横向更抓不住），
    --   车就一边走一边往坡下横着滑；平地上慢慢停住。下滑力按地面坡度（Map.height 前后左右各 6 格）
    do
      local slL = st.slL or 0
      if st.airS or inWater or not st.surf or not st.surf.mu then   -- 横滑也只在雪、冰、雪路上
        slL = 0
      else
        local e = 6
        local gx = (Map.height(st.pos.X + e, st.pos.Z) - Map.height(st.pos.X - e, st.pos.Z)) / (2 * e)
        local gz = (Map.height(st.pos.X, st.pos.Z + e) - Map.height(st.pos.X, st.pos.Z - e)) / (2 * e)
        local fB = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
        local rB = V(-fB.Z, 0, fB.X)
        local t2 = gx * gx + gz * gz
        local cosT = 1 / math.sqrt(1 + t2)
        local GS = 18 / math.max(cosT, 0.3)   -- 同上面前后方向的 18 × 坡（sin）：这里按梯度折算
        local aLat = -(gx * rB.X + gz * rB.Z) * GS * cosT * cosT   -- 横坡方向的下滑加速度（正的往右）
        local mu = (sf.mu or 0.7) * (tracked and 1.0 or 0.85)
        local hold = mu * 18 * cosT * ((math.abs(v) > 2) and 0.8 or 1.15)   -- 开着走：动摩擦；停着：静摩擦大一点
        if math.abs(slL) < 0.3 and math.abs(aLat) <= hold then
          slL = 0
        else
          local fr = mu * 18 * 0.9 * cosT
          local nv = slL + aLat * dt - ((slL ~= 0) and math.sign(slL) or math.sign(aLat)) * fr * dt
          nv -= nv * math.min(1, 0.6 * dt)   -- 履带横着犁雪：越滑越费劲（横滑速度有个头，不会一直加速）
          if slL ~= 0 and math.sign(nv) ~= math.sign(slL) and math.abs(aLat) <= hold then nv = 0 end
          slL = math.clamp(nv, -d.speed * 0.35, d.speed * 0.35)
        end
      end
      st.slL = slL
    end
    st.steer = approach(st.steer, str, dt * 4)
    -- 往前挪（顺着 travel：车在侧滑时位置跟着真正的去向走）：坡太陡、不会游的下水、撞到房子都走不动；擦着墙的顺着墙滑过去
    local fwd = V(-math.sin(st.travel), 0, -math.cos(st.travel))
    local step = st.speed * dt
    -- 横着滑的那一下（上面 slL）：撞房子、下深水就停
    if math.abs(st.slL or 0) > 0.05 then
      local rB = V(math.cos(st.yaw), 0, -math.sin(st.yaw))
      local sv = rB * st.slL * dt
      local np = st.pos + sv
      local hb = Map.height(np.X, np.Z)
      local o = st.pos + V(0, Map.ground(st.pos.X, st.pos.Z) - st.pos.Y + d.hullH * 0.55, 0)
      local hit = workspace:Raycast(o, sv.Unit * (d.W * 0.5 + sv.Magnitude + 0.5), mapParams)
      if hit or (hb < -2.5 and not d.amphib) then
        if hit then bump(math.abs(st.slL)) end
        st.slL = 0
      else
        st.pos = np
      end
    end
    if math.abs(step) > 1e-4 then
      local np = st.pos + fwd * step
      local h0 = Map.height(st.pos.X, st.pos.Z)
      local h1 = Map.height(np.X, np.Z)
      local blocked = false
      if h1 < -2.5 and not d.amphib and not carried then blocked = true end
      -- 坡度按地面（海里按水面）算：比约 40° 陡上不去。按前方 4 格取样——原来按这一帧走的距离算（每帧零点几格），
      --   岸边零点几格的小坎就算成陡坡，两栖车卡在水线上不去；帧率越高越容易卡
      local probe = math.max(4, math.abs(step))
      local pa = st.pos + fwd * math.sign(step) * probe
      local ha = Map.height(pa.X, pa.Z)
      if not blocked and ha > 0.5 and (ha - math.max(h0, -0.5)) / probe > 0.85 then blocked = true end
      local slide = nil
      if not blocked then
        local o = st.pos + V(0, Map.ground(st.pos.X, st.pos.Z) - st.pos.Y + d.hullH * 0.55, 0)
        local mv = fwd * math.sign(step)
        local res = workspace:Raycast(o, mv * (d.L * 0.5 + math.abs(step) + 0.5), mapParams)
        if res then
          -- 撞上房子、码头（UE5 的车擦着墙会顺着墙滑，不是一下钉死）：正着撞停下；斜着蹭上去顺着墙走、掉速、车头往墙的方向扭过去
          local n = V(res.Normal.X, 0, res.Normal.Z)
          local head = 1
          if n.Magnitude > 0.2 then
            n = n.Unit
            head = math.clamp(-mv:Dot(n), 0, 1)   -- 1 = 正面撞上
            local tan = mv - n * mv:Dot(n)
            if head < 0.62 and tan.Magnitude > 0.05 then
              tan = tan.Unit
              local back = workspace:Raycast(o, tan * (d.L * 0.5 + math.abs(step) + 0.5), mapParams)
              if not back then slide = { dir = tan, head = head } end
            end
          end
          bump(math.abs(st.speed) * head)
          if not slide then blocked = true end
        end
      end
      if slide then
        np = st.pos + slide.dir * math.abs(step) * (1 - slide.head * 0.6)
        st.speed -= st.speed * math.min(1, slide.head * 3.5 * dt)
        local hd = (step > 0) and slide.dir or -slide.dir
        local tYaw = math.atan2(-hd.X, -hd.Z)
        local turn = angR(st.yaw, tYaw) * math.min(1, dt * 2.6 * (1 - slide.head))
        st.yaw += turn
        st.travel += turn
        st.wallT = os.clock()
      end
      -- 工事、钢刺猬（FortView 给的）：往里开就停（已经卡在里面的让它开出来）
      if not blocked and G.solidAt then
        local ahead = st.pos + fwd * math.sign(step) * (d.L * 0.45 + math.abs(step))
        if G.solidAt(ahead, d.W * 0.4) and not G.solidAt(st.pos, d.W * 0.4) then blocked = true end
      end
      if blocked then
        if math.abs(st.speed) > 12 and G.shake then G.shake(0.25) end
        bump(math.abs(st.speed))
        st.speed = -st.speed * 0.1   -- 顶住了：往回弹一点
        st.travel = st.yaw
      else
        st.pos = np
      end
      -- 侧面别嵌进墙里（擦着墙走、车身转过来贴着墙时前面那条射线就碰不到墙了）：车身两侧前中后各打一条短射线，
      --   哪边太近就往外推（每边取最深的那一下，不叠加）
      local fB = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
      local rB = V(-fB.Z, 0, fB.X)
      local gy = Map.ground(st.pos.X, st.pos.Z)
      local pushT = V()
      for _, sd in ipairs({ -1, 1 }) do
        local best, bestPen = nil, 0
        for _, u in ipairs({ -0.36, 0, 0.36 }) do
          local o = V(st.pos.X, gy + d.hullH * 0.55, st.pos.Z) + fB * (u * d.L)
          local res = workspace:Raycast(o, rB * sd * (d.W / 2 + 0.6), mapParams)
          if res then
            local n = V(res.Normal.X, 0, res.Normal.Z)
            local pen = d.W / 2 + 0.3 - (res.Position - o).Magnitude
            if pen > bestPen and n.Magnitude > 0.2 then best, bestPen = n.Unit, pen end
          end
        end
        if best then
          pushT += best * math.min(bestPen, 2)
          -- 正往墙里走：撞一下（声音、震屏按切进去的角度）、蹭着墙掉速，去向改成顺着墙（不一直往墙里顶）
          local sg = (st.speed >= 0) and 1 or -1
          local fT = V(-math.sin(st.travel), 0, -math.cos(st.travel)) * sg
          local into = -fT:Dot(best)
          if into > 0 then
            bump(math.abs(st.speed) * math.max(into, 0.3))
            st.speed -= st.speed * math.min(1, (0.25 + 1.6 * into) * dt)
            local nd = fT - best * fT:Dot(best)
            if nd.Magnitude > 0.05 then
              nd = nd.Unit * sg
              local ty = math.atan2(-nd.X, -nd.Z)
              st.travel = ty
              st.yaw += angR(st.yaw, ty) * math.min(1, dt * 2.4)   -- 车身被墙掰过去、顺着墙
            end
          end
        end
      end
      if pushT.Magnitude > 1e-3 then
        st.pos += pushT
        st.wallT = os.clock()
      end
      -- 撞树（钢城 Map.TREES，用户 11-26「要有可以撞倒的树」）：车身（按车头方向的矩形）碰到的树往车走的方向倒（擦着边撞的往外偏一点），
      --   本地马上倒、再告诉服务器（Scenery.lua 的 G.treeKnock）；坦克几乎不掉速，轮式车、轻车掉得多，车身颠一下
      if Map.TREES and G.treeKnock and math.abs(st.speed) > 1.2 then
        local p = st.pos
        local fT = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
        local rT = V(-fT.Z, 0, fT.X)
        for _, t in ipairs(Map.treesNear(p.X, p.Z, d.L * 0.5 + 6, treeBuf)) do
          if not (G.treeIsDown and G.treeIsDown(t.id)) then
            local rel = V(t.x - p.X, 0, t.z - p.Z)
            local a, b = rel:Dot(fT), rel:Dot(rT)
            if math.abs(a) < d.L * 0.5 + t.r and math.abs(b) < d.W * 0.5 + t.r then
              local dir = ((st.speed >= 0) and fT or -fT) + rT * (math.clamp(b / (d.W * 0.5 + t.r), -1, 1) * 0.35)
              G.treeKnock(t, dir.Unit, "veh")
              local heavy = tracked or (d.cat == "tank")
              st.speed *= heavy and (1 - 0.05 * t.s) or (1 - 0.3 * t.s)
              if G.shake then G.shake(heavy and 0.06 or 0.16) end
            end
          end
        end
      end
    end
    -- 真地形（terrainLift）：0.15 秒量一次，平滑着跟（量一下差太多就在 Output 说一声，好对照）
    st.tProbeT = (st.tProbeT or 0) - dt
    if st.tProbeT <= 0 then
      st.tProbeT = 0.15
      local L = terrainLift(d, st.pos, st.yaw)
      st.tLiftT = L or 0
      if L and math.abs(L) > 0.75 and not st.tLiftSaid then
        st.tLiftSaid = true
        print(string.format("[地形] 车底下看得见的地面比算的高度%s %.2f 格：车已经按看得见的地面摆", (L > 0) and "高" or "低", math.abs(L)))
      end
    end
    st.tLift = (st.tLift or 0) + ((st.tLiftT or 0) - (st.tLift or 0)) * math.min(1, dt * 6)
    local base = baseAt(d, st.pos, st.yaw, false)
    st.slopeS = math.clamp(base.LookVector.Y, -1, 1)   -- 车头朝上为正（下一帧的上坡阻力）
    -- 腾空（UE5 的车冲过坡顶会飞起来）：地面只能托住车、拉不住——车照「上一刻往上的速度 + 重力」走的抛物线比地面高，就离地飞一会儿；
    --   开下陡坎也一样往下掉。在天上不能加速、转向，车身慢慢往前栽；落地按砸下来的速度：悬挂压一下、镜头一沉、震屏、一声闷响、扬一团土
    local gY = base.Position.Y
    local A = st.airS
    if A then
      A.vy -= GRAV * dt
      A.y += A.vy * dt
      A.t += dt
      if A.y <= gY or A.t > 4 then
        st.airS = nil
        st.gVy = 0
        land(math.max(0, -A.vy))
      else
        base = base + V(0, A.y - gY, 0)
      end
    elseif st.gY0 and not inWater and not st.dropT then
      local gv = st.gVy or 0
      local fall = st.gY0 + gv * dt - 0.5 * GRAV * dt * dt
      if gY < fall - 0.06 and (gv > 2.5 or fall - gY > 1.2) and math.abs(st.speed) > 6 then
        st.airS = { y = fall, vy = gv - GRAV * dt, t = 0, p0 = st.sus and st.sus.p, r0 = st.sus and st.sus.r }
        st.airN = (st.airN or 0) + 1   -- 测试用：飞起来过几次
        base = base + V(0, fall - gY, 0)
      else
        st.gVy = math.clamp((gY - st.gY0) / math.max(dt, 1e-3), -80, 80)
      end
    end
    st.gY0 = gY
    if st.dropT then   -- 从艇上开下来：车底从甲板高度顺下来
      st.dropT += dt
      local k = math.clamp(st.dropT / 0.6, 0, 1)
      local far = st.dropAt and (V(st.pos.X, 0, st.pos.Z) - V(st.dropAt.X, 0, st.dropAt.Z)).Magnitude > 40   -- 被挪走了（服务器拉回、测试瞬移）：不接着顺
      if k >= 1 or not st.dropFrom or far then
        st.dropT, st.dropFrom, st.dropAt = nil, nil, nil
      else
        local y = st.dropFrom + (base.Position.Y - st.dropFrom) * (k * k * (3 - 2 * k))
        base = base + V(0, y - base.Position.Y, 0)
      end
      st.sus = nil
    else
      -- 悬挂：车身跟地形起伏是弹簧阻尼（坑坑洼洼的地上一颠一颠，不是硬贴上去）；加速车头抬、刹车点头、转弯往外侧倾（轮式车软一点）
      local tp = math.asin(math.clamp(base.LookVector.Y, -1, 1))
      local tr = math.asin(math.clamp(base.RightVector.Y, -1, 1))
      local AS = st.airS
      if AS and AS.p0 then   -- 在天上：保持起飞时的姿态，车头慢慢往下栽
        tp = AS.p0 - math.min(0.3, 0.28 * AS.t)
        tr = AS.r0 or tr
      end
      local soft = tracked and 1 or 1.4
      local dynP = math.clamp(st.accel * 0.0055 * soft, -0.08, 0.08)
      local dynR = math.clamp(v * (st.yr or 0) * 0.0045 * soft, -0.06, 0.06)
      local S = st.sus
      if not S or (V(st.pos.X, 0, st.pos.Z) - V(S.x, 0, S.z)).Magnitude > 30 then   -- 第一次 / 被挪走了：直接贴上
        S = { y = base.Position.Y, vy = 0, p = tp, vp = 0, r = tr, vr = 0 }
        st.sus = S
      end
      S.x, S.z = st.pos.X, st.pos.Z
      -- 掉帧时分几步算，免得弹簧算飞：每步不超过 1/120 秒（用户 11-25「坦克一直在抽搐」——原来一帧超过 1/45 秒才分 3 步，
      --   卡到一帧 0.3 秒时每步 0.1 秒，车身弹簧照样算飞；一帧最多按 0.12 秒算，卡一下不会把车弹上天）
      local dtS = math.min(dt, 0.12)
      local n = math.max(1, math.ceil(dtS * 120 - 1e-6))
      local h = dtS / n
      for _ = 1, n do
        local function spring(x, vx, target, k, z)
          vx += (k * (target - x) - 2 * math.sqrt(k) * z * vx) * h
          return x + vx * h, vx
        end
        -- 脆感（用户 11-25 晚）：弹簧硬一点、阻尼大一点——起步、刹车一下点头就收住，不再一颤一颤
        S.y, S.vy = spring(S.y, S.vy, base.Position.Y, 240, 0.72)
        S.p, S.vp = spring(S.p, S.vp, tp + dynP, 150, 0.74)
        S.r, S.vr = spring(S.r, S.vr, tr + dynR, 150, 0.74)
      end
      if S.y < base.Position.Y - 0.25 then S.y, S.vy = base.Position.Y - 0.25, math.max(S.vy, 0) end   -- 不陷进地里
      S.y = math.min(S.y, base.Position.Y + 1.5)
      local fwdF = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
      local p0 = V(st.pos.X, S.y, st.pos.Z)
      base = CFrame.lookAt(p0, p0 + fwdF) * CFrame.Angles(S.p, 0, S.r)
    end
    st.pos = base.Position
    st.root = base * CF(0, d.H / 2, 0)
  end

  -- 射线不算的东西：自己这辆车（实体、样子、碰撞盒、履带板）、自己的人、特效、车内的零件。
  --   用户 11-26「坦克瞄准一个坦克 火控计算机会越过那个坦克瞄准后面的」：原来把所有车的样子（G.viewFolder）都排除了，
  --   测距、准星、火控解算都穿过敌车量到后面的地上；现在只排除自己的，别的车（敌我、靶车、残骸）都挡射线
  local function rayEx()
    local ex = {}
    local function add(x) if x then table.insert(ex, x) end end
    add(ownBox)
    if st and st.em then
      add(st.em)
      local v = G.views and G.views[st.em]
      add(v and v.model)
    end
    add(me.Character)
    add(G.fxFolder)
    add(G.interiorNow)
    return ex
  end
  -- 准星打到哪：从镜头往前打一条射线（不算自己的车）
  local function aimPoint()
    local o, dir = cam.CFrame.Position, cam.CFrame.LookVector
    local ex = rayEx()
    aimParams.FilterDescendantsInstances = ex
    local res = G.rayFar(o, dir * 4000, aimParams)   -- 开了 streaming：远处没加载的地形按地形高度算（Stream.lua）
    return res and res.Position or (o + dir * 4000), res ~= nil
  end

  local function aimTurret(dt)
    local d = st.d
    local w = VD.W[d.weapons[st.wi] or ""]
    local base = st.root * CF(0, -d.H / 2, 0)
    local piv = (base * CF(d.turret.pivot) * CF(d.gun.pivot)).Position
    local ap = st.aimPt or (piv + base.LookVector * 100)
    local rel = base:VectorToObjectSpace(ap - piv)
    local horiz = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
    local wantYaw = math.deg(math.atan2(rel.X, -rel.Z))
    local wantPitch = math.deg(math.atan2(rel.Y, math.max(horiz, 1)))
    local am = w and w.kind == "shell" and not st.aimNoDrop and BAL.GUN[d.weapons[st.wi] or ""] and BAL.ammo(d.weapons[st.wi], st.fcs.am)
    local f = st.fcs
    if am then   -- 坦克炮：弹道计算机按到瞄准点的距离、弹种算超高角（瞄准镜里瞄准点在测的距离上；车外是准星打到的地方——自动测距）
      -- 手动方式（火控方式开关拨到 MANUAL：弹道计算机不工作）：炮管不抬超高角，要炮长自己用分划往上留
      local se = (f.mode == 3) and 0 or BAL.superElev(am, math.sqrt(horiz * horiz + rel.Y * rel.Y) / BAL.S, math.atan2(rel.Y, math.max(horiz, 1)))
      wantPitch += math.deg(se)
      st.fcsSE = se
      -- 炮管热弯曲没修正的那部分（开炮炮管上热下凉往下弯；炮口基准更新以后的变化计算机不知道）：炮比瞄准线低一点；校炮偏差（密位）
      wantPitch -= (f.droop - f.mrs) * 0.0573
      wantPitch += (f.bore[2] or 0) * 0.05625
      wantYaw += (f.bore[1] or 0) * 0.05625
    elseif w and w.kind == "shell" and not st.aimNoDrop then   -- 炮弹下坠：按飞行时间抬一点（防空火控给的点已经算过下坠）
      local tFly = horiz / w.speed
      local drop = 0.5 * workspace.Gravity * 0.55 * (w.drop / 0.55) * tFly * tFly
      wantPitch += math.deg(math.atan2(drop, math.max(horiz, 1)))
    elseif w and w.kind == "arty" then   -- 曲射：炮管抬到大约 45°（只是好看，落点按准星算）
      wantPitch = math.clamp(25 + horiz / 120, 25, 60)
    end
    -- 手动方式：炮塔动力关了，手摇方向机、高低机（每秒十来度、几度）
    local manual = f.mode == 3
    local trav = d.turret.trav * (manual and 0.22 or 1) * ((st.em and st.em:GetAttribute("WtTrav")) or 1)   -- 炮塔驱动坏了 / 炮长没了：转得慢（Wt.lua）
      * ((st.em and st.em:GetAttribute("ModTrav")) or 1)   -- 研究了改装「炮塔驱动」：转得快（WtMods）
    st.ty = (st.ty + math.clamp(angDiff(st.ty, wantYaw), -trav * dt, trav * dt)) % 360
    st.gp = approach(st.gp, math.clamp(wantPitch, d.turret.elev[1], d.turret.elev[2]), (manual and 6 or 35) * dt)
    -- 遥控武器站（M1A2 的 CROWS）：自己转向准心、M2 自己俯仰（用户：机枪也要能转动），比炮塔快
    --   车长单独操纵它的时候（车里看 CROWS 屏：Interior.lua 给 st.rwsPt）朝车长瞄的那一点，炮塔还归炮长的准星
    if d.rws then
      local myW, mpW = VD.rwsAim(d, base, st.ty, st.rwsPt or ap)
      st.my = st.my + math.clamp(angDiff(st.my, myW), -d.rws.trav * dt, d.rws.trav * dt)
      st.my = (st.my + 180) % 360 - 180
      st.mp = approach(st.mp, mpW, d.rws.rate * dt)
    end
  end

  -- 这一刻开炮，炮弹落在哪（用户 11-27「坦克准心对标战雷」）：第三人称的炮管标记、穿深指示都按它——
  --   原来标记顺着「已经加了超高角」的炮管直线放到瞄准点那么远：1000 米外 3BK18M 比瞄准点高 6.4 米，穿深射线从车顶上过去、圈一直是白的。
  --   现在：炮管方向减去按落点距离算的超高角（迭代两次），打射线找到真打到的东西；炮塔基本转到位、却打在比瞄准点近得多的地面 / 墙上 = 炮口被挡
  -- full：打射线（每秒 15 次）；不 full：用上次量到的落点距离，按炮管现在的指向重算标记位置（每帧，便宜，标记跟得上）
  local function gunImpact(full)
    local d = st.d
    if not (d.turret and d.gun) then st.gunHit = nil return end
    local base = st.root * CF(0, -d.H / 2, 0)
    local gcf = VD.gunCF(d, base, st.ty, st.gp)
    local o = gcf.Position
    local wid = weaponId()
    local w = wid and VD.W[wid]
    local am = w and w.kind == "shell" and BAL.GUN[wid] and BAL.ammo(wid, st.fcs.am)
    local function seOf(Rm)
      if am then return BAL.superElev(am, math.max(Rm, 1), 0) end
      if w and w.kind == "shell" and (w.speed or 0) > 0 then
        local dist = Rm * BAL.S
        local tFly = dist / w.speed
        return math.atan2(0.5 * workspace.Gravity * (w.drop or 0.55) * tFly * tFly, math.max(dist, 1))
      end
      return 0
    end
    local old = st.gunHit
    if not full and old then
      local dir = (gcf * CFrame.Angles(-seOf(old.R), 0, 0)).LookVector
      old.o, old.dir, old.p = o, dir, o + dir * (old.R * BAL.S)
      return
    end
    local Rw = st.aimPt and (st.aimPt - o).Magnitude / BAL.S or 1000
    local Rm = Rw
    local len = math.min(4000, Rw * BAL.S * 1.3 + 120)   -- 只打到瞄准点再远一点
    local dir, hit = gcf.LookVector, nil
    aimParams.FilterDescendantsInstances = rayEx()
    for i = 1, 2 do
      dir = (gcf * CFrame.Angles(-seOf(Rm), 0, 0)).LookVector
      local h = (i == 1) and G.rayFar(o, dir * len, aimParams) or workspace:Raycast(o, dir * len, aimParams)
      if h then hit = h elseif i == 1 then break end
      if not h then break end
      local R2 = (h.Position - o).Magnitude / BAL.S
      if math.abs(R2 - Rm) < Rm * 0.03 then Rm = R2 break end   -- 距离差不多：不用再打第二次
      Rm = R2
    end
    local p = o + dir * (Rm * BAL.S)
    local blocked = false
    if hit and st.aimPt then
      local want = st.aimPt - o
      local inst, veh = hit.Instance, false
      while inst and inst ~= workspace do
        if inst:GetAttribute("EntId") then veh = true break end
        inst = inst.Parent
      end
      local aligned = want.Magnitude > 1 and gcf.LookVector:Dot(want.Unit) > math.cos(math.rad(2.5))
      blocked = (not veh) and aligned and Rm < math.min(0.9 * Rw, Rw - 7)
    end
    st.gunHit = { p = p, o = o, dir = dir, R = Rm, inst = hit and hit.Instance, blocked = blocked }
  end
  G.driveGunHit = function() return st and st.gunHit end   -- VehHud / WtTank、测试

  -- 坐在车里（第一人称）：方向键转炮塔、抬压炮（用户 11-22：「坦克第一人称的话，炮管转动用上下左右键，然后 WASD 继续管车体移动」）
  --   瞄准线记在世界坐标里（炮塔有稳定：车身怎么转、怎么颠，炮还指着原来的方向）；← → 最快按炮塔的转速、↑ ↓ 最快每秒 10°，
  --   刚按下去慢（点一下动零点几度，好细瞄），按住 0.6 秒到全速；火控照常按距离抬炮（aimTurret 的弹道修正，瞄准线打到哪炮弹落到哪）。
  --   别处改了瞄准点（猎-歼：车长把炮塔调到热像仪看的方向；武器站就是炮塔的车，鼠标转的就是炮塔），瞄准线从那儿接着转
  local function arrows()
    return (UIS:IsKeyDown(Enum.KeyCode.Left) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.Right) and 1 or 0),
      (UIS:IsKeyDown(Enum.KeyCode.Up) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.Down) and 1 or 0)
  end
  local function keyAim(dt)
    local d = st.d
    if not d.turret or not d.gun then return false end
    local kx, ky = arrows()
    local base = st.root * CF(0, -d.H / 2, 0)
    local piv = (base * CF(d.turret.pivot) * CF(d.gun.pivot)).Position
    local k = st.kAim
    if not k or (st.aimPt and k.pt and (st.aimPt - k.pt).Magnitude > 0.5) then
      local dv = st.aimPt and (st.aimPt - piv) or VD.gunCF(d, base, st.ty, st.gp).LookVector
      dv = (dv.Magnitude > 1e-3) and dv.Unit or base.LookVector
      k = { yaw = math.atan2(-dv.X, -dv.Z), pitch = math.asin(math.clamp(dv.Y, -1, 1)), hold = 0 }
      st.kAim = k
    end
    k.hold = (kx ~= 0 or ky ~= 0) and math.min(1, k.hold + dt / 0.6) or 0
    local ramp = 0.25 + 0.75 * k.hold
    k.yaw += kx * math.rad(d.turret.trav) * ramp * dt
    k.pitch += ky * math.rad(10) * ramp * dt
    local dirW = (CFrame.Angles(0, k.yaw, 0) * CFrame.Angles(k.pitch, 0, 0)).LookVector
    -- 炮俯仰到头了，瞄准线也停在那儿（不然一直按着，松开以后炮还要往回走一大段）
    local rel = base:VectorToObjectSpace(dirW)
    local ry = math.atan2(rel.X, -rel.Z)
    local rp = math.atan2(rel.Y, math.sqrt(rel.X * rel.X + rel.Z * rel.Z))
    local lo, hi = math.rad(d.turret.elev[1]), math.rad(d.turret.elev[2])
    if rp < lo or rp > hi then
      rp = math.clamp(rp, lo, hi)
      dirW = base:VectorToWorldSpace(V(math.sin(ry) * math.cos(rp), math.sin(rp), -math.cos(ry) * math.cos(rp)))
      k.yaw, k.pitch = math.atan2(-dirW.X, -dirW.Z), math.asin(math.clamp(dirW.Y, -1, 1))
    end
    local ex = rayEx()
    aimParams.FilterDescendantsInstances = ex
    -- 瞄准点只管方向和距离（火控按距离抬炮）：炮管长度以内碰到的（贴着工事、石头、屋檐停车）不算，不然 aimTurret 按一格远的点算出来的俯仰角不对
    local res = G.rayFar(piv, dirW * 4000, aimParams)
    local dist = res and (res.Position - piv).Magnitude or 4000
    st.aimPt = piv + dirW * math.max(dist, 10)
    k.pt, k.hit = st.aimPt, res and res.Instance
    return true
  end
  G.driveKeyAim = function() return st and st.kAim end   -- 测试用

  local function weaponId() return st.d.weapons[st.wi] end

  ---------------------------------------------------------------- 火控（坦克炮：Ballistics.lua）
  -- 用户 11-22 晚（钢铁猛兽 M1A2 热像截图：M830 HEAT-T、1790 米，曳光弹在左上方）：「开镜开炮炮弹从左上方落下去，符合真实物理学和火控系统」
  --   R 激光测距：瞄准线打到哪、多远（5 米一档；4 公里外、没打到东西是没回波 ----）；Q 换弹种（换了要重新装填）；
  --   没测距时按战斗瞄准距离装定（穿甲弹 1200 米、破甲 / 多用途弹 900 米）——打得比这远的目标就会打低；
  --   测距那一下记下瞄准线跟踪的角速度，乘飞行时间就是提前量（再测一次更新，10 秒后作废）
  -- 科技树改装（WtMods）：原厂车只有第一种弹，研究了「第二种弹」「第三种弹」才能换（服务器出车时写 ModAmmo）
  local function ammoList(wid)
    local list = BAL.GUN[wid]
    local n = st and st.em and st.em:GetAttribute("ModAmmo")
    if list and type(n) == "number" and n < #list then return table.move(list, 1, math.max(1, n), 1, {}) end
    return list
  end
  local function fcsAmmo()
    local wid = weaponId()
    if not (wid and BAL.GUN[wid]) then return nil end
    local al = ammoList(wid)
    if st.fcs.am and not table.find(al, st.fcs.am) then st.fcs.am = al[1] end
    local a, k = BAL.ammo(wid, st.fcs.am)
    st.fcs.am = k
    return a, wid
  end
  local function sightEye()
    local d = st.d
    local base = st.root * CF(0, -d.H / 2, 0)
    return (VD.turretCF(d, base, st.ty) * CF(d.sight or V(0, d.H * 0.3, 0))).Position
  end
  -- 激光一路上打到的东西：草丛、烟、玻璃、细杆子、半透明的这些挡不住，光接着往前走——每碰到一个就是一个回波（最多三个，真车的测距机也是三个）
  local function porous(inst)
    if not inst or not inst:IsA("BasePart") then return false end
    -- 车、飞机的实体（服务器的碰撞盒，本身是透明的）算回波——用户 11-26「火控计算机会越过那个坦克瞄准后面的」：
    --   车的样子（客户端模型）射线打不中，打得中的只有这个透明碰撞盒，原来按「透明」当成穿得过去，激光穿过车量到后面的地
    local m = inst:FindFirstAncestorWhichIsA("Model")
    if m and m:GetAttribute("EntId") ~= nil then return false end
    local mt = inst.Material
    if mt == Enum.Material.Glass or mt == Enum.Material.ForceField or mt == Enum.Material.Fabric or mt == Enum.Material.LeafyGrass or mt == Enum.Material.Grass then return true end
    if inst.Transparency >= 0.3 then return not inst.CanCollide end   -- 看不见的：挡炮弹的碰撞盒（房子）算，别的不算
    local sz = inst.Size
    return math.min(sz.X, sz.Y, sz.Z) < 0.5 and math.max(sz.X, sz.Y, sz.Z) < 12
  end
  local laseNow
  local function lase()
    local a = fcsAmmo()
    if not a then return end
    local f = st.fcs
    local P = st.fcsP
    if P and (P.rangeT + P.solve) > 0.05 then   -- 科技树的火控：测距（激光那一下就测，光学测距仪 / 估距要对一会儿）+ 弹道计算机解算，过一会儿才出结果
      if f.estT and os.clock() < f.estT then return end
      local wait = P.rangeT + P.solve
      f.estT = os.clock() + wait
      f.estimating = true
      if G.sfx then pcall(G.sfx, "uiClick") end
      local myF = f
      local early = (P.err == 0) and laseNow(myF, false, 0, true) or nil   -- 激光：按按下去那一刻量，结果等计算机算完再用
      task.delay(wait, function()
        if not st or st.fcs ~= myF then return end
        myF.estimating = nil
        if early then early() else laseNow(myF, P.err > 0, P.err) end
      end)
      return
    end
    -- 没有激光测距机的车（VehDefs 的 lrf = false：豹 1、M60A1、BMP-1）：按 R 是车长估距——两秒以后报一个数，差上下 8% 左右（战雷历史模式）
    if st.d.lrf == false then
      if f.estT and os.clock() < f.estT then return end
      f.estT = os.clock() + 2.2
      f.estimating = true
      if G.sfx then pcall(G.sfx, "uiClick") end
      local myF = f
      task.delay(2.2, function()
        if not st or st.fcs ~= myF then return end
        myF.estimating = nil
        laseNow(myF, true)
      end)
      return
    end
    laseNow(f, false)
  end
  -- errK：估距误差（比例，默认 8%）；later：只量、先不写结果，返回一个「写结果」的函数（火控解算完再调）
  laseNow = function(f, est, errK, later)
    if f.arm == false and not est then   -- 激光测距机拨在保险上：不出光
      if G.sfx then pcall(G.sfx, "dry") end
      return
    end
    local eye = sightEye()
    local dir = st.sight and cam.CFrame.LookVector or ((st.aimPt and (st.aimPt - eye).Magnitude > 1) and (st.aimPt - eye).Unit or cam.CFrame.LookVector)
    local ex = rayEx()
    local rets = {}
    local o = eye
    local left = BAL.MAXR * BAL.S
    local laseHit = nil   -- 最后打到的实物（自动跟踪锁它）
    for _ = 1, 3 do
      aimParams.FilterDescendantsInstances = ex
      local res = G.rayFar(o, dir * left, aimParams, true)   -- 激光打到没加载的远处山坡：按地形高度算回波（Stream.lua）
      if not res then break end
      local m = (res.Position - eye).Magnitude / BAL.S
      if m >= 50 then table.insert(rets, m) end
      laseHit = res.Instance
      if not porous(res.Instance) then break end
      table.insert(ex, res.Instance)
      local step = (res.Position - o).Magnitude + 0.05
      o = o + dir * step
      left -= step
      if left <= 0 then break end
    end
    local multi = #rets > 1
    local m = rets[1] and ((f.lrf == "FIRST") and rets[1] or rets[#rets]) or nil
    if est and m then m = m * (1 + (math.random() * 2 - 1) * (errK or 0.08)) end   -- 车长估的：上下差 8% 以内（火控好的少）
    local ry, rp = f.ry or 0, f.rp or 0
    -- 自动目标跟踪（猎歼式火控）：激光打在一辆车上就锁住它
    local hitM = nil
    if st.fcsP and st.fcsP.track and laseHit then
      local inst = laseHit
      while inst and inst.Parent and inst.Parent ~= workspace and not inst:GetAttribute("EntId") do inst = inst.Parent end
      if inst and inst:IsA("Model") and inst:GetAttribute("EntId") and inst ~= st.em then hitM = inst end
    end
    local function apply()
      f.laseT = os.clock()
      f.multi = multi
      f.est = est or nil
      if m then f.R, f.noRet = math.floor(m / (est and 50 or 5) + 0.5) * (est and 50 or 5), false
      else f.R, f.noRet = nil, true end
      f.man = nil
      f.leadY, f.leadP = ry, rp   -- 测距那一刻跟踪的角速度（弧度 / 秒）：提前量
      f.trk = hitM
      if G.sfx then pcall(G.sfx, "uiClick") end
    end
    if later then return apply end
    apply()
  end
  G.driveLase = function() if st then lase() end end   -- 测试用；车里计算机控制面板的 LRF 键（Interior.lua）也走这里
  -- 手动装定距离（M1A1 计算机控制面板 CCP 的 RANGE 键，Interior.lua）：弹道计算机按这个距离算超高角（没有提前量）；nil 清掉、回到战斗瞄准距离
  G.driveRange = function(m)
    if not st then return end
    local f = st.fcs
    if m then f.R, f.noRet, f.laseT, f.man = math.clamp(math.floor(m / 5 + 0.5) * 5, 50, BAL.MAXR), false, nil, true
    else f.R, f.noRet, f.laseT, f.man = nil, false, nil, nil end
  end
  local function cycleAmmo(key)
    local wid = weaponId()
    local list = wid and ammoList(wid)
    if not list then return end
    local k = key
    if not (k and table.find(list, k)) then
      local i = table.find(list, st.fcs.am or list[1]) or 1
      k = list[i % #list + 1]
    end
    if k == st.fcs.am then return end
    st.fcs.am = k
    local w = VD.W[wid]
    st.next[wid] = math.max(st.next[wid] or 0, os.clock() + (w and w.rate or 6))   -- 换弹种：膛里那发退不出来，装填手重新装一发
    if G.sfx then pcall(G.sfx, "uiClick") end
  end
  G.driveAmmo = function(key) if st then cycleAmmo(key) end end   -- 车里炮长控制面板的弹种键（Interior.lua）也走这里
  -- 战斗瞄准距离：这个弹种调过的（调整页）或者弹种自己的（穿甲 1200、破甲 / 多用途 900……）
  local function bsRange(am)
    local f = st and st.fcs
    return (f and f.am and f.bsR[f.am]) or (am and am.bs) or 1000
  end
  -- 表尺（用户 11-27「坦克的开镜按照战雷的做」）：PageUp / PageDown 每次 100 米装定距离（0 ~ 4000 米）——炮按这个距离抬超高角，
  --   镜里的表尺跟着挪（装定 0 时刻度全在中心下面，截图那样；装定 1200 时「12」在中心）；之后再测距会盖掉它
  local function sightRangeStep(dir)
    if not st then return end
    local am = fcsAmmo()
    if not am then return end
    local f = st.fcs
    local r0 = f.R or bsRange(am)
    local nv = math.clamp(math.floor(r0 / 100 + 0.5) * 100 + dir * 100, 0, 4000)
    f.R, f.noRet, f.laseT, f.man, f.est, f.multi, f.trk = nv, false, nil, true, nil, false, nil
    if G.sfx then pcall(G.sfx, "uiClick") end
  end
  G.driveSightRange = sightRangeStep   -- 测试用
  -- 车长用望远镜估距（望远镜里按 R）：两秒报个数，差上下 6% 左右；报出来的距离装定到炮上（同战雷车长测距）
  local function binoRange()
    if not st or not fcsAmmo() then return end
    local f = st.fcs
    if f.estT and os.clock() < f.estT then return end
    f.estT = os.clock() + 2.0
    f.estimating = true
    if G.sfx then pcall(G.sfx, "uiClick") end
    local myF = f
    task.delay(2.0, function()
      if not st or st.fcs ~= myF then return end
      myF.estimating = nil
      laseNow(myF, true, 0.06)
    end)
  end
  G.driveBinoRange = function() binoRange() end   -- 测试用
  -- 车里的炮长面板（Interior.lua 的动作）：都改 st 上的火控状态，开着镜的马上重画
  G.driveFcs = function() return st and st.fcs, st end   -- 读状态（面板页面、测试）
  G.driveBattlesight = function()   -- 战斗瞄准：清掉测的 / 手动的距离，回到这个弹种的战斗瞄准距离
    if not st then return end
    local f = st.fcs
    f.R, f.noRet, f.laseT, f.man, f.multi = nil, false, nil, nil, false
  end
  G.driveBsRange = function(key, m)   -- 调整页：改一个弹种的战斗瞄准距离（米；nil 回到默认）
    if not st then return end
    st.fcs.bsR[key] = m and math.clamp(math.floor(m / 50 + 0.5) * 50, 200, 2500) or nil
  end
  G.driveBsOf = function(key)
    if not st then return nil end
    local list = BAL.GUN[weaponId() or ""]
    local am = key and BAL.AMMO and BAL.AMMO[key]
    return st.fcs.bsR[key] or (am and am.bs), list
  end
  G.driveMrs = function()   -- 炮口基准更新：量一下现在炮管弯了多少，弹道计算机按它修正（之后再热、再冷又会差）
    if st then st.fcs.mrs = st.fcs.droop end
  end
  G.driveBore = function(daz, del)   -- 校炮偏差（密位）：调整页的四向键；都给 nil 是归零
    if not st then return end
    local b = st.fcs.bore
    if daz == nil and del == nil then b[1], b[2] = 0, 0 return end
    b[1] = math.clamp(b[1] + (daz or 0), -5, 5)
    b[2] = math.clamp(b[2] + (del or 0), -5, 5)
  end
  G.driveSetFcs = function(k)   -- 火控方式 1 正常 / 2 应急 / 3 手动
    if not st then return end
    st.fcs.mode = math.clamp(math.floor(k or 1), 1, 3)
  end
  G.driveSet = function(field, value)   -- 稳定器、分划 / 符号亮度、分划照明、热像增益 / 电平、激光回波 / 保险
    if not st then return end
    if field == "lrf" or field == "arm" then st.fcs[field] = value else st[field] = value end
    syncZooms()
    applyMode()
  end
  G.driveZoomStep = function(i)   -- 视场：给第几档（1 起），不给就下一档
    if not st then return end
    syncZooms()
    st.zoom = i and math.clamp(i, 1, #ZOOMS) or (st.zoom % #ZOOMS + 1)
  end
  G.driveZooms = function() syncZooms() return ZOOMS, st and st.zoom end
  G.driveWeapon = function(i)   -- 武器选择（布雷德利：25 毫米炮 / 并列机枪）
    if st and st.d.weapons[i] then st.wi = i end
  end
  G.driveApplySight = function() if st then syncZooms() applyMode() end end

  local function tryFire()
    local wid = weaponId()
    local w = wid and VD.W[wid]
    if not w or st.locked then return end
    if st.safe then return end   -- 武器总开关拨在保险（布雷德利炮长面板上的 ARM / SAFE，Interior.lua）
    if (w.kind == "shell" or w.kind == "arty" or w.kind == "sam" or w.kind == "atgm") and st.em and st.em:GetAttribute("WtGun") == false then   -- 战雷式伤害：炮长没了、炮闩 / 炮管坏了、正在修
      local t0 = os.clock()
      if t0 > (st.wtGunMsg or 0) and G.toast then
        st.wtGunMsg = t0 + 1.5
        G.toast(T((st.em:GetAttribute("WtFix") ~= nil) and "wt.fixing" or "wt.noGun"), "bad")
      end
      return
    end
    local t = os.clock()
    if t < (st.next[wid] or 0) then return end
    local ammo = G.S and G.S.veh and G.S.veh.ammo and G.S.veh.ammo[wid]
    if ammo and ammo[1] <= 0 and ammo[2] <= 0 then return end
    -- 射速选择（布雷德利 M242：HI 高速 / LO 低速一半 / SS 单发：扳一下打一发）：只管机关炮（射速快于半秒一发的炮）
    local rofK = (w.kind == "shell" and w.rate < 0.5 and st.rof == "LO") and 2 or 1
    local crewK = (w.kind == "shell" and st.em and st.em:GetAttribute("CrewRel")) or 1   -- 乘员技能「装填」（服务器同样乘）
    local rackK = (w.kind == "shell" and BAL.GUN[wid] and st.em and st.em:GetAttribute("RdyK")) or 1   -- ④ 待发弹架空了装得慢（服务器 Wt.lua 同样乘）
    st.next[wid] = t + w.rate * rofK * crewK * rackK
    if BAL.GUN[wid] then st.fcs.droop = math.min(0.9, st.fcs.droop + 0.07) end   -- 每打一发炮管热一点、往下弯一点（毫弧度）
    local base = st.root * CF(0, -st.d.H / 2, 0)
    -- 火控的残余散布（WtMods.FCS 的 sig 密位：弹道表、横风、炮耳倾斜没修正的那点）：这一发炮管差一点点
    local P = BAL.GUN[wid] and st.fcsP
    if P and P.sig > 0 then
      local function g() return (math.random() + math.random() + math.random() - 1.5) * 1.15 end   -- 近似正态
      st.gp += g() * P.sig * 0.0573
      st.ty += g() * P.sig * 0.0573
    end
    local mz = VD.muzzle(st.d, base, st.ty, st.gp, VD.mgWhich(st.d, wid), st.my, st.mp)
    -- 地空导弹（铠甲-S1 的 57E6）：要先用防空火控 Q 雷达锁住一架飞机（AaFcs.lua），锁住的那架就是目标
    local samTgt = nil
    if w.kind == "sam" then
      local fs = G.aaFcsState and G.aaFcsState()
      samTgt = fs and fs.lockId
      if not samTgt then
        st.next[wid] = t + 0.4
        if G.toast then G.toast(T("veh.samNeedLock"), "info") end
        return
      end
    end
    -- 开火这一刻的炮塔、炮管、机枪塔角度一起发过去：服务器按它摆好炮管再算炮口（用户：弹道顺着枪管和炮管、开火位置和枪口对上）
    G.R.Drive:FireServer({ op = "fire", w = wid, dir = mz.LookVector, aim = st.aimPt, ty = st.ty, gp = st.gp, my = st.my, mp = st.mp,
      am = BAL.GUN[wid] and st.fcs.am or nil, tgt = samTgt,
      disp = (st.arty and G.artyBloom) and G.artyBloom() or nil })   -- 炮兵视角里散布圈胀开了多少（0～1，服务器按它散落点）   -- am 坦克炮这一发是什么弹（服务器按它的初速、阻力打出去）；tgt 地空导弹的目标
    if w.kind == "gun" and G.gunFx then   -- 自己打的机枪：本地马上画曳光（服务器发回来的特效会跳过自己打的，原来开车打机枪什么都看不见）
      local dir = mz.LookVector
      local ex = rayEx()
      aimParams.FilterDescendantsInstances = ex
      local res = G.rayFar(mz.Position, dir * (w.range or 900), aimParams)
      G.gunFx(wid, mz.Position, res and res.Position or (mz.Position + dir * (w.range or 900)), true)
    end
    if w.kind == "shell" or w.kind == "arty" then
      if G.vehRecoil then G.vehRecoil(st.id) end
      if G.shake then G.shake((w.dmg > 300) and 0.35 or 0.06) end
      -- 整车被后坐力推一下（用户 11-25 晚「那你做战雷手感吧」）：炮朝前时车头一扬、车身往后一坐，朝侧面时炮那一侧抬起来；
      --   炮越大晃得越厉害（120 毫米约 2～3°，小炮只抖一下），悬挂弹簧再把它晃回来
      local S = st.sus
      if S then
        local big = math.clamp((w.dmg or 0) / 600, 0.12, 1.1)
        local rel = math.rad(st.ty or 0)   -- 炮塔相对车体：正的往右
        S.vp = (S.vp or 0) + big * 0.95 * math.cos(rel)
        S.vr = (S.vr or 0) + big * 0.75 * math.sin(rel)
        if not st.airS then st.speed = (st.speed or 0) - big * 1.1 * math.cos(rel) end   -- 往后一顿（很小）
      end
      -- 镜头跟着后坐一下（追尾镜头往后上方一顿；瞄准镜里往上一跳再晃回来）、镜里一阵炮口烟（VehHud 按 fireT 画）
      st.kickA, st.kickT = (w.dmg > 300) and 1 or 0.35, 0
      st.kick = st.kickA * 0.3
      st.fireT = t
    end
    if ammo then   -- 本地先扣（服务器的数半秒后来校正）
      ammo[1] -= 1
      if ammo[1] <= 0 and ammo[2] > 0 then
        local n = math.min(w.mag, ammo[2])
        ammo[1], ammo[2] = n, ammo[2] - n
        st.next[wid] = t + math.max(w.rate, w.reload or 0)
      end
    end
  end

  G.driveTryFire = tryFire   -- 测试用（tools/test/ia_rws.luau）

  ---------------------------------------------------------------- 手机：方向键、开火、烟幕、瞄准镜、模式、下车

  if UIS.TouchEnabled then
    local touch = { thr = 0, str = 0 }
    local tb = ui.frame(gui, UDim2.fromOffset(250, 170), UDim2.new(0, 20, 1, -190), RGB(0, 0, 0), 1)
    tb.Visible = false
    local function hold(text, pos, onDown, onUp)
      local b = ui.button(tb, text, UDim2.fromOffset(64, 64), pos, RGB(30, 36, 42))
      b.BackgroundTransparency = 0.35
      b.InputBegan:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then onDown() end end)
      b.InputEnded:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then onUp() end end)
      return b
    end
    hold("▲", UDim2.fromOffset(93, 0), function() touch.thr = 1 end, function() touch.thr = 0 end)
    hold("▼", UDim2.fromOffset(93, 104), function() touch.thr = -1 end, function() touch.thr = 0 end)
    hold("◀", UDim2.fromOffset(20, 52), function() touch.str = -1 end, function() touch.str = 0 end)
    hold("▶", UDim2.fromOffset(166, 52), function() touch.str = 1 end, function() touch.str = 0 end)
    local rb = ui.frame(gui, UDim2.fromOffset(240, 220), UDim2.new(1, -250, 1, -330), RGB(0, 0, 0), 1)
    rb.Visible = false
    local function tap(text, pos, f)
      local b = ui.button(rb, text, UDim2.fromOffset(64, 64), pos, RGB(30, 36, 42))
      b.BackgroundTransparency = 0.35
      b.TextSize = 14
      b.Activated:Connect(f)
      return b
    end
    local fb = hold("●", UDim2.fromOffset(0, 0), function() end, function() end)
    fb.Parent = rb
    fb.Size = UDim2.fromOffset(90, 90)
    fb.Position = UDim2.fromOffset(140, 120)
    fb.InputBegan:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch and st then st.firing = true tryFire() end end)
    fb.InputEnded:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch and st then st.firing = false end end)
    tap("◎", UDim2.fromOffset(60, 140), toggleSight)
    tap(T("drv.optic"), UDim2.fromOffset(60, 66), nextMode)
    tap(T("drv.smoke"), UDim2.fromOffset(140, 40), smoke)
    tap("F", UDim2.fromOffset(0, 0), function() G.R.Drive:FireServer({ op = "exit" }) end)
    tap("1/2", UDim2.fromOffset(170, -30), function() if st then st.wi = (st.wi % #st.d.weapons) + 1 end end)
    G.touchDrive = touch
    G.touchDriveUI = { tb, rb }
  end

  ---------------------------------------------------------------- 输入

  local NUMK = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4,
    [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6 }   -- 战雷那样主炮几种弹一种一个数，M1A2 四种弹 + 机枪要到 5
  UIS.InputBegan:Connect(function(io, gp)
    if gp or not st then return end
    local k = io.KeyCode
    if io.UserInputType == Enum.UserInputType.MouseButton1 then
      if G.interiorHover and G.interiorHover() then return end   -- 车里对着屏幕边的按键：左键是按键，不开炮（Interior.lua）
      st.firing = true
      tryFire()
    elseif io.UserInputType == Enum.UserInputType.MouseButton2 then
      toggleSight()
    elseif k == Enum.KeyCode.V or (k == Enum.KeyCode.N and st.sight) then   -- 光电模式：昼光 → 夜视 → 热成像白热 → 黑热（没开镜时 N 是夜视仪，Night.lua）
      nextMode()
    elseif k == Enum.KeyCode.Z then
      syncZooms()
      st.zoom = st.zoom % #ZOOMS + 1
    elseif k == Enum.KeyCode.R then   -- 激光测距（坦克炮的火控）；望远镜里是车长估距
      if st.binoc then binoRange() else lase() end
    elseif (k == Enum.KeyCode.PageUp or k == Enum.KeyCode.PageDown) and not (G.interiorOn and G.interiorOn()) then
      sightRangeStep((k == Enum.KeyCode.PageUp) and 1 or -1)   -- 表尺（用户 11-27 照战雷）：装定距离每次 100 米
    elseif k == Enum.KeyCode.C and not (G.interiorOn and G.interiorOn()) then   -- 车长望远镜（用户 11-27）
      G.driveBinoc()
    elseif k == Enum.KeyCode.Q then   -- 换弹种（穿甲 / 破甲 / 多用途……）
      cycleAmmo()
    elseif NUMK[k] and G.radioOpen and G.radioOpen() then   -- 无线电菜单开着（WtComms.lua，O）：数字键选无线电，不换弹
    elseif NUMK[k] then   -- 3 / 4：车顶重机枪、改装的车顶加特林
      local i = NUMK[k]
      -- 战雷式（WtTank.lua）：数字键照底部弹药栏一格一个数——主炮的弹种在前（1 穿甲、2 破甲……），再是机炮、机枪
      if not (G.wtKeySlot and G.wtKeySlot(st, i)) and st.d.weapons[i] then st.wi = i end
    elseif k == Enum.KeyCode.M then   -- 烟幕弹（用户 11-25「烟幕改成m」）
      smoke()
    elseif k == Enum.KeyCode.X then   -- 透视自己的车：按住显示、松开恢复（XrayOwn.lua；用户 11-26「x应该是摁住显示3d 松手就恢复原样」）
      if G.ownXrayHold then
        st.xrSight = st.sight   -- 开着瞄准镜：先退到车外看自己的车，松手再回镜里（原来镜里按 X 什么都看不到）
        if st.sight then toggleSight() end
        G.ownXrayHold(true)
      end
    elseif k == Enum.KeyCode.Y and st.em and st.em:GetAttribute("WtC") ~= nil then   -- 战雷式：着火先灭火，没着火就修车（再按一次取消修）
      G.R.Act:FireServer(st.em:GetAttribute("WtF") and "wtExt" or "wtFix")
    elseif k == Enum.KeyCode.G and not (G.interiorOn and G.interiorOn()) then   -- 战雷式侦察（WtMatch.lua）：轻型车对着准星下的敌车按，全队看得见它 30 秒
      local aim = st.aimPt or (workspace.CurrentCamera.CFrame.Position + workspace.CurrentCamera.CFrame.LookVector * 1000)
      local from = (st.sight and workspace.CurrentCamera.CFrame.Position) or (st.root.Position + V(0, st.d.H or 6, 0))
      G.R.Act:FireServer("wtScout", from, aim)
    elseif k == Enum.KeyCode.K and not (G.interiorOn and G.interiorOn()) then   -- 战雷式火炮支援：准星下那块地落一轮炮弹（冷却 2 分钟）
      if st.aimPt then G.R.Act:FireServer("wtArty", st.aimPt) end
    elseif k == Enum.KeyCode.J and st.em and st.em:GetAttribute("Plow") ~= nil then   -- 扫雷犁（坦克改装）：放下 / 升起（升起要 11 秒）
      G.R.Drive:FireServer({ op = "plow", down = (st.em:GetAttribute("Plow") or 0) < 1 })
    elseif (k == Enum.KeyCode.F or k == Enum.KeyCode.E or k == Enum.KeyCode.Space) and not (G.hangarActive and G.hangarActive()) then   -- 用户：空格键脱离载具（F / E 也还能用）
      -- 战雷式（不当步兵）：没有「下车」——原来按空格下车 = 这辆车判毁、人阵亡（用户 11-25「在车上按空格也不要自动阵亡了」）；
      --   空格改成刹车（physics），回机库是长按 H（Hud.lua）
      G.R.Drive:FireServer({ op = "exit" })
    end
  end)
  UIS.InputEnded:Connect(function(io)
    if st and io.UserInputType == Enum.UserInputType.MouseButton1 then st.firing = false end
    if io.KeyCode == Enum.KeyCode.X and G.ownXrayHold then   -- 松开 X：透视收起，原来在瞄准镜里的回镜里
      G.ownXrayHold(false)
      if st and st.xrSight and not st.sight then toggleSight() end
      if st then st.xrSight = nil end
    end
  end)
  -- 滚轮（用户 11-25「画面缩放升高的时候 先往后 再往上……参考坦克世界的画面缩放逻辑」）：
  --   第三人称往后滚，镜头先往后拉（臂长 0.6 → 1.6 倍），拉到头再往上升（绕着转的点抬高十几米，站得高看得远）；
  --   往前滚拉近，拉到最近再往前滚一格进瞄准镜；瞄准镜里滚轮换倍率，最低倍再往后滚退回第三人称（同坦克世界的狙击模式）
  G.tpZoom = G.tpZoom or 0.2
  UIS.InputChanged:Connect(function(io)
    if not st or io.UserInputType ~= Enum.UserInputType.MouseWheel then return end
    if G.settingsShown and G.settingsShown() then return end
    if st.arty and G.artyWheel then G.artyWheel(io.Position.Z) return end   -- 炮兵视角：镜头升降
    if st.sight then
      syncZooms()
      if io.Position.Z < 0 and st.zoom <= 1 and not (G.interiorOn and G.interiorOn()) then toggleSight() return end
      st.zoom = math.clamp(st.zoom + ((io.Position.Z > 0) and 1 or -1), 1, #ZOOMS)
      return
    end
    if G.interiorOn and G.interiorOn() then return end   -- 车里：滚轮归车内视角
    if io.Position.Z > 0 then
      if G.tpZoom <= 0.001 then toggleSight() return end
      G.tpZoom = math.max(0, G.tpZoom - 0.1)
    else
      G.tpZoom = math.min(1, G.tpZoom + 0.1)
    end
  end)

  G.R.Drive.OnClientEvent:Connect(function(m)
    if type(m) ~= "table" or not st then return end
    if m.op == "fix" and typeof(m.cf) == "CFrame" then   -- 服务器不认：拉回去
      local base = m.cf * CF(0, -st.d.H / 2, 0)
      local look = base.LookVector
      st.pos, st.yaw = base.Position, math.atan2(-look.X, -look.Z)   -- 车速不清零（11-26：原来每次拉回车速归零，卡一下就停）
      st.root = m.cf
    end
  end)

  ---------------------------------------------------------------- 每帧

  local SENS = 0.0042
  function G.stepDrive(dt)
    local S = G.S
    local vs = S and S.alive and S.veh or nil
    if vs and (vs.fort or vs.air or vs.ship or vs.pass) then vs = nil end   -- 操作工事归 Gunner 管，飞机归 Fly 管，舰艇归 Sail 管
    if vs and (not st or st.id ~= vs.id) then
      if st then stop() end
      begin(vs)
    elseif not vs and st then
      stop()
    end
    if not st then return end
    if not st.em.Parent then stop() return end
    local d = st.d
    st.fcs.droop = math.max(0, st.fcs.droop - dt * 0.0012)   -- 炮管慢慢凉回来（打满了十来分钟凉透）
    -- 稳定器关（面板上的开关，或者手动方式）：瞄准线不再稳在世界里，跟着车体转、颠（车身转多少，镜里的画面、炮就跟着偏多少）
    do
      local lv = st.root.LookVector
      local hy, hp = math.atan2(-lv.X, -lv.Z), math.asin(math.clamp(lv.Y, -1, 1))
      if st.lastHy and (st.stab == false or st.fcs.mode == 3) then
        local dy = (hy - st.lastHy + math.pi) % (2 * math.pi) - math.pi
        local dp = hp - st.lastHp
        st.camYaw += dy
        st.camPitch = math.clamp(st.camPitch + dp, -0.75, 0.6)
        if st.kAim then st.kAim.yaw += dy st.kAim.pitch += dp st.kAim.pt = nil end
      end
      st.lastHy, st.lastHp = hy, hp
    end
    local om = ownModel()
    if om and om.Parent ~= ownBox then om.Parent = ownBox end
    st.locked = vs.locked
    -- 镜头转动（坐在车里看的时候鼠标归内饰的镜头：Interior.lua，炮塔不跟着转）
    UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
    -- 车里的观瞄设备（车长热像仪 / 周视镜、CROWS……）开着时也算在车里：鼠标归那个设备，炮塔守着炮长原来的准星
    local inside = G.interiorOn and (G.interiorOn() or G.interiorOptic ~= nil) and not st.sight
    local md = G.mouseDelta and G.mouseDelta(st.sight) or UIS:GetMouseDelta()   -- 设置里的灵敏度、开镜灵敏度、反转 Y（Settings.lua）
    local sens = SENS * (st.sight and (ZOOMS[st.zoom] / 70) or (st.binoc and (GS.binoFov / 70)) or 1)
    if st.arty and G.artyMouse then G.artyMouse(md, dt)   -- 炮兵视角：鼠标挪地上的瞄准点
    elseif not inside then
      st.camYaw -= md.X * sens
      st.camPitch = math.clamp(st.camPitch - md.Y * sens, -0.75, 0.6)
    end
    -- 自动目标跟踪（猎歼式火控，测距锁住的车）：瞄准线自己跟着它（按炮塔最快转速）；动鼠标、退镜、目标没了就解除
    local trk = st.fcs.trk
    if trk then
      if not st.sight or not trk.Parent or md.Magnitude > 8 or trk:GetAttribute("Dead") then st.fcs.trk = nil
      else
        local dv = trk:GetPivot().Position - cam.CFrame.Position
        local wy = math.atan2(-dv.X, -dv.Z)
        local wp = math.atan2(dv.Y, math.sqrt(dv.X * dv.X + dv.Z * dv.Z))
        local r = math.rad(d.turret and d.turret.trav or 30) * dt
        st.camYaw += math.clamp((wy - st.camYaw + math.pi) % (2 * math.pi) - math.pi, -r, r)
        st.camPitch = math.clamp(st.camPitch + math.clamp(wp - st.camPitch, -r * 0.6, r * 0.6), -0.75, 0.6)
      end
    end
    if st.sight and d.turret then   -- 炮长瞄准镜里（第一人称）方向键也能转炮、抬压炮（细瞄：刚按下去慢，按住 0.6 秒到全速）
      local kx, ky = arrows()
      st.sightHold = (kx ~= 0 or ky ~= 0) and math.min(1, (st.sightHold or 0) + dt / 0.6) or 0
      local ramp = 0.25 + 0.75 * st.sightHold
      st.camYaw += kx * math.rad(d.turret.trav) * ramp * dt
      st.camPitch = math.clamp(st.camPitch + ky * math.rad(10) * ramp * dt, -0.75, 0.6)
    end
    -- 车
    if st.locked then   -- 在气垫艇上：跟着服务器
      st.root = st.em.Root.CFrame
      local base = st.root * CF(0, -d.H / 2, 0)
      st.pos = base.Position
      local look = base.LookVector
      st.yaw = math.atan2(-look.X, -look.Z)
      st.travel, st.airS = nil, nil
      st.speed = 0
    else
      physics(dt)
    end
    -- 镜头
    local dirCam = CFrame.Angles(0, st.camYaw, 0) * CFrame.Angles(st.camPitch, 0, 0)
    local artyCF, artyAim = nil, nil
    if st.arty and G.artyStep then
      artyCF, artyAim = G.artyStep(st, dt)
      if not artyCF then st.arty = false end   -- 换了不是曲射的武器：退出炮兵视角
    end
    if artyCF then
      cam.CFrame = artyCF
      st.aimPt = artyAim
      st.camShake = CFrame.new()
    elseif st.binoc then
      -- 车长望远镜（用户 11-27）：车长从指挥塔（VehDefs 的 cupola）探出头、8 倍；炮塔照样跟着看的方向转，R 车长估距
      local base = st.root * CF(0, -d.H / 2, 0)
      local tcf = d.turret and VD.turretCF(d, base, st.ty) or base
      local cup = d.cupola or (d.turret and d.turret.size and V(0, d.turret.size.Y * 0.5, 0)) or V(0, d.H * 0.5, 0)
      local eye = (tcf * CF(cup)).Position + V(0, 1.6, 0)
      cam.FieldOfView = cam.FieldOfView + (GS.binoFov - cam.FieldOfView) * math.min(1, dt * 10)
      cam.CFrame = CFrame.lookAt(eye, eye + dirCam.LookVector)
      st.aimPt = aimPoint()
      st.camShake = CFrame.new()
    elseif st.sight then
      local base = st.root * CF(0, -d.H / 2, 0)
      local gcf = VD.gunCF(d, base, st.ty, st.gp)
      local tcf = VD.turretCF(d, base, st.ty)
      local eye = (tcf * CF(d.sight)).Position
      local zi = (G.opticsDead and G.opticsDead()) and 1 or st.zoom   -- 观瞄打坏了：只剩最低倍率
      cam.FieldOfView = cam.FieldOfView + (ZOOMS[zi] - cam.FieldOfView) * math.min(1, dt * 10)
      local am = fcsAmmo()
      if am then
        -- 坦克炮（火控）：分划中心是瞄准线——鼠标给的方向；炮跟着瞄准线走、再抬超高角、加提前量。
        --   瞄准线离炮的指向（去掉超高角）最多 6°（主瞄准镜头部反射镜的活动范围），再远就被炮塔拖着走（炮塔转速有限）
        local want = dirCam.LookVector
        local glos = (gcf * CFrame.Angles(-(st.fcsSE or 0), 0, 0)).LookVector
        local ang = math.acos(math.clamp(want:Dot(glos), -1, 1))
        local MAXOFF = math.rad(6)
        if ang > MAXOFF and ang < math.pi - 1e-3 then   -- 从炮的瞄准线往鼠标方向转 6°（球面插值）
          local sa = math.sin(ang)
          want = (glos * math.sin(ang - MAXOFF) + want * math.sin(MAXOFF)) / sa
          st.camYaw = math.atan2(-want.X, -want.Z)
          st.camPitch = math.clamp(math.asin(math.clamp(want.Y, -1, 1)), -0.75, 0.6)
        end
        cam.CFrame = CFrame.lookAt(eye, eye + want)
        -- 跟踪的角速度（弧度 / 秒，平滑 0.3 秒）：测距那一下记下来算提前量
        local f = st.fcs
        if f.ly then
          local k = math.min(1, dt / 0.3)
          f.ry += (((st.camYaw - f.ly + math.pi) % (2 * math.pi) - math.pi) / math.max(dt, 1e-3) - f.ry) * k
          f.rp += ((st.camPitch - f.lp) / math.max(dt, 1e-3) - f.rp) * k
        end
        f.ly, f.lp = st.camYaw, st.camPitch
        -- 炮对准瞄准线上测出的那个距离的点（视差：炮在瞄准镜旁边，往里收到那一点），提前量按飞行时间
        local R = math.max(f.R or bsRange(am), 50)   -- 表尺能拨到 0（PageDown）：瞄准点、飞行时间按至少 50 米算
        local tof = BAL.flight(am, R)
        -- 提前量：只有正常方式（应急、手动方式没有角速度传感器给的提前量）
        local lead = f.mode == 1 and f.R ~= nil and f.laseT ~= nil and (os.clock() - f.laseT < 10)
        -- 科技树的火控（WtMods.FCS）：没有角速度传感器的（第一代以前）没有提前量；数字火控随时按跟踪的角速度算（动态提前量）
        local P = st.fcsP
        local dyn = P ~= nil and P.lead == 2
        if P then lead = f.mode == 1 and f.R ~= nil and P.lead > 0 and (dyn or (f.laseT ~= nil and os.clock() - f.laseT < 10)) end
        local ly = st.camYaw + (lead and (dyn and f.ry or (f.leadY or 0)) * tof or 0)
        local lp = st.camPitch + (lead and (dyn and f.rp or (f.leadP or 0)) * tof or 0)
        local dirL = (CFrame.Angles(0, ly, 0) * CFrame.Angles(lp, 0, 0)).LookVector
        st.aimPt = eye + dirL * (R * BAL.S)
        st.fcsAim = { eye = eye, R = R, tof = tof, bs = f.R == nil, lead = lead }
      else
        cam.CFrame = CFrame.lookAt(eye, eye + gcf.LookVector)
        -- 瞄准镜里的准星就是炮的指向；鼠标给的是想去的方向
        local o = eye
        local want = dirCam.LookVector
        aimParams.FilterDescendantsInstances = rayEx()
        local res = G.rayFar(o, want * 4000, aimParams)
        st.aimPt = res and res.Position or (o + want * 4000)
      end
    else
      local center = st.root.Position + V(0, d.H * 0.4, 0)
      -- 用户 11-19（MWT 截图）：开坦克时镜头离车近一点、从后上方往下看——车占画面四成来宽、在下半屏（原来 L × 1.25 + 14，车只占两成）
      -- 滚轮缩放（坦克世界）：前六成先往后拉，后四成往上升（转点抬高；头顶有桥、屋顶就只抬到那下面）
      G.tpZs = G.tpZs or G.tpZoom
      G.tpZs += (G.tpZoom - G.tpZs) * math.min(1, dt * 7)
      local back = math.min(G.tpZs / 0.6, 1)
      local rise = math.max(0, (G.tpZs - 0.6) / 0.4)
      local dist = (d.L * 0.62 + 8) * (0.62 + back)
      local up = d.H * 0.6 + dist * 0.18
      if rise > 0.01 then
        local lift = (14 + d.L * 1.2) * rise ^ 1.4
        local hit = workspace:Raycast(center, V(0, lift + 3, 0), camParams)
        if hit then lift = math.max(0, hit.Distance - 3) end
        center += V(0, lift, 0)
      end
      if st.hv then   -- 开着气垫艇：镜头拉远、抬高，整条艇在画面里
        local L = VD.LCAC
        dist, up = L.size.Z * 1.15 + 18, d.H * 0.6 + 8
      end
      -- 弹簧臂（VehCam.lua，用户 11-20：照 UE5 的水平升级）：跟随有惯性、加速往后坠、刹车往前冲、落地一沉，臂碰到山坡房子平滑缩近；
      --   路面越颠镜头越抖（石头地 > 草地 > 土路），越快视野越宽；镜头跟着车身侧倾歪一点
      local spd = math.clamp(math.abs(st.speed) / math.max(d.speed, 1), 0, 1.3)
      local p3 = st.root.Position
      st.vel3 = st.lastP3 and (p3 - st.lastP3) / math.max(dt, 1e-3) or V()
      st.lastP3 = p3
      local rough = (st.surf and st.surf.rough or 0.7) * (st.hv and 0.35 or 1) * (st.airS and 0.2 or 1)
      local camCF, camShake, fov = G.vehCam({ key = "drive", pivot = center, dir = dirCam, dist = dist, up = up, vel = st.vel3, dt = dt,
        -- 战雷的坦克镜头：不跟着车身歪（侧倾 0）、视野不随车速变（原来歪两成、全速宽 7°）——画面稳，车在镜头底下晃（11-26）
        rough = rough, speedK = spd, up3 = nil, params = camParams, fov0 = G.fov3 or 70, fovK = 1.5, pushK = 0.035, maxPush = 2,
        follow = 14, maxLag = 1.4 })   -- 脆感：镜头跟紧车（原来跟随弹簧 9、最多落后 2.5 格，开起来发飘）   -- 第三人称视野：设置里调
      cam.CFrame = camCF
      cam.FieldOfView = fov
      st.camShake = camShake
      local im = inside and G.interiorState and G.interiorState().mode
      if inside and im ~= "free" and keyAim(dt) then   -- 车里：方向键转炮（导演镜头里方向键挪镜头，炮塔守着原来的准星）
      elseif not inside or not st.aimPt then st.aimPt = aimPoint() end
    end
    -- 防空车（Cat = aa、用炮打的）：防空火控显示（AaFcs.lua，用户 11-22：「高射炮加一个电子屏标记点位然后打」）——
    --   敌机标框、提前量圈；准星压在圈上、或者 Q 雷达锁定以后，炮按火控算的点打（已经含弹道下坠，aimTurret 不再加）
    st.aimNoDrop = nil
    do
      local wa = VD.W[weaponId() or ""]
      if d.cat == "aa" and wa and (wa.kind == "shell" or wa.kind == "sam") and d.turret and d.gun and G.aaFcs then
        local base = st.root * CF(0, -d.H / 2, 0)
        local piv = (base * CF(d.turret.pivot) * CF(d.gun.pivot)).Position
        local gl = VD.gunCF(d, base, st.ty, st.gp).LookVector
        -- 地空导弹（铠甲-S1）：导弹自己追，火控不算提前量（当成飞得极快、不下坠的弹：炮塔对着飞机），Q 锁住的那架就是导弹的目标
        local sam = wa.kind == "sam"
        local r = G.aaFcs({ origin = piv, speed = sam and 1e6 or wa.speed, g = sam and 0 or workspace.Gravity * (wa.drop or 0.55), range = wa.range or 2000,
          look = cam.CFrame.LookVector, side = me:GetAttribute("Side"), hullYaw = st.yaw, gunYaw = math.atan2(-gl.X, -gl.Z) })
        if r.aimPt then st.aimPt, st.aimNoDrop = r.aimPt, true end
      end
    end
    aimTurret(dt)
    do   -- 这一发的落点：射线每秒 15 次，标记位置每帧跟炮管
      st.ghT = (st.ghT or 0) - dt
      local full = st.ghT <= 0 or st.gunHit == nil
      if full then st.ghT = 1 / 15 end
      local ok, err = pcall(gunImpact, full)
      if not ok then st.gunHit = nil G.driveGunErr = err end   -- 测试看
    end
    -- 路面颠簸的细抖（瞄准、炮塔都按没晃的镜头算过了）
    if st.camShake and not st.sight and not G.noShake then cam.CFrame = cam.CFrame * st.camShake end   -- 设置里能关镜头晃动
    -- 开炮的镜头后坐（瞄准、炮塔都按没晃的镜头算过了，这里只是看起来晃）
    -- 镜头后坐：0.05 秒冲到最大（先快后慢；原来开炮那一帧一下子跳过去），再按原来的速度回来
    if st.kickT then
      st.kickT += dt
      local t = st.kickT
      local e = (t < 0.05) and (1 - (1 - t / 0.05) ^ 2) or math.max(0, 1 - (t - 0.05) * 2.4)
      st.kick = (st.kickA or 0) * e
      if e <= 0 and t > 0.05 then st.kickT = nil end
    else
      st.kick = 0
    end
    if st.kick > 0 then
      local k = st.kick * st.kick
      local tt = os.clock()
      if st.sight then
        cam.CFrame = cam.CFrame * CFrame.Angles(k * 0.05 + math.noise(tt * 26, 1.3) * k * 0.012, math.noise(tt * 26, 4.1) * k * 0.012, math.noise(tt * 21, 8.2) * k * 0.02)
      else
        cam.CFrame = cam.CFrame * CF(0, k * 0.5, k * 2.2) * CFrame.Angles(k * 0.035, 0, math.noise(tt * 18, 2.9) * k * 0.02)
      end
    end
    do   -- 发动机声
      local thrK = (UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.S)) and 1 or ((G.touchDrive and G.touchDrive.thr ~= 0) and 1 or 0)
      engineStep(dt, thrK, math.abs(st.speed) / math.max(d.speed, 1))
    end
    -- 连发
    local w = VD.W[weaponId() or ""]
    if st.firing and w and w.rate < 0.5 and not (st.rof == "SS" and w.kind == "shell") then tryFire() end   -- 单发：按住不连发
    -- 报给服务器（每秒 15 次）
    st.sendT -= dt
    if st.sendT <= 0 and not st.locked then
      st.sendT = 1 / 15
      G.R.Drive:FireServer({ op = "state", cf = st.root, ty = st.ty, gp = st.gp, sp = st.speed, my = d.rws and st.my or nil, mp = d.rws and st.mp or nil })
    end
    -- 炮现在指着哪（追尾镜头里画一个黄十字）
    local base = st.root * CF(0, -d.H / 2, 0)
    local gcf = VD.gunCF(d, base, st.ty, st.gp)
    local gp = gcf.Position + gcf.LookVector * math.max(30, (st.aimPt - gcf.Position).Magnitude)
    local sp, on = cam:WorldToViewportPoint(gp)
    gunMark.Visible = on and not st.sight and not st.binoc and not G.vehHudOn and not inside
    gunMark.Position = UDim2.fromOffset(sp.X, sp.Y)
    cross.Visible = not st.sight and not st.binoc and not G.vehHudOn and not inside
    -- 仪表
    local em = st.em
    local hp, mx = em:GetAttribute("Hp") or 1, em:GetAttribute("MaxHp") or 1
    hpBar.Size = UDim2.fromScale(math.clamp(hp / mx, 0, 1), 1)
    hpBar.BackgroundColor3 = ui.hpColor(hp / mx)
    local tk = em:GetAttribute("TreeKey")   -- 科技树出的车写科技树里的名字（借来的型号也写自己的）
    local vn = tk and T("tree." .. tk) or T("veh." .. d.id)
    vName.Text = st.hv and T("ui.lcacOn", T("veh.lcac"), vn) or (vn .. (st.locked and ("   " .. T("ui.lcac")) or ""))
    st.help = st.hv and "ui.lcacHelp" or nil   -- 底部键位说明（UI.lua）：开艇和开车不一样
    local wid = weaponId()
    local ammo = vs.ammo and wid and vs.ammo[wid]
    local kmh = math.floor(math.abs(st.speed) / 2.8 * 3.6 + 0.5)
    local rel = 1
    if wid and w then
      local left = (st.next[wid] or 0) - os.clock()
      local full = (ammo and ammo[1] == w.mag and left > w.rate) and (w.reload or w.rate) or w.rate
      rel = 1 - math.clamp(left / math.max(full, 0.01), 0, 1)
    end
    relBar.Size = UDim2.fromScale(rel, 1)
    vInfo.Text = T("ui.speed", kmh) .. "    " .. (wid and T("vw." .. wid) or "") .. (ammo and ("  " .. ammo[1] .. " / " .. ammo[2]) or "")
      .. "    " .. T("ui.smokeLeft", vs.smoke or 0) .. "    " .. T("sight." .. MODES[st.mode])
    -- 瞄准镜：分划、表尺、方位、读数（GunSight.lua，用户 11-27 照战雷）；颗粒；热成像的高亮隔一会儿重挑一次
    if st.sight then
      local am, gwid = fcsAmmo()
      local f = st.fcs
      local lv = cam.CFrame.LookVector
      local info = { am = am, wid = gwid, amKey = f.am, fcs = f, yaw = math.atan2(-lv.X, -lv.Z), lrf = st.d.lrf ~= false,
        ready = rel >= 0.999, trk = f.trk, est = f.est }
      if am then
        info.R0 = f.R or bsRange(am)
        info.bs = bsRange(am)
        -- 炮管实际指着哪（去掉超高角）：炮塔追着瞄准线转，还没转过来时小十字偏在一边
        local base = st.root * CF(0, -d.H / 2, 0)
        local gcf = VD.gunCF(d, base, st.ty, st.gp)
        local glos = (gcf * CFrame.Angles(-(st.fcsSE or 0), 0, 0)).LookVector
        info.markPt = cam.CFrame.Position + glos * 2000
        local parts = {}
        if f.mode == 2 then table.insert(parts, "EMER") elseif f.mode == 3 then table.insert(parts, "MAN") end
        if st.stab == false then table.insert(parts, "STAB OFF") end
        if f.arm == false then table.insert(parts, "LRF SAFE") end
        if math.abs(f.droop - f.mrs) > 0.25 then table.insert(parts, "MRS") end
        if f.man then table.insert(parts, "MAN RNG") end
        if f.estimating then table.insert(parts, (st.d.lrf == false) and "RANGING" or "CALC") end   -- 测距 / 弹道计算机解算中
        if f.trk then table.insert(parts, "TRACK") end   -- 自动目标跟踪锁着
        if f.R ~= nil and f.multi == true then table.insert(parts, "MULTI") end   -- 多回波
        info.status = table.concat(parts, "   ")
      else
        -- 不是坦克炮（机炮、机枪）：镜头顺着炮管看，中心就是炮的指向；小十字画鼠标想去的地方（炮塔正往那转）
        info.markPt = st.aimPt
      end
      GS.step(st, info)
      do   -- 光电模式；热像写上是第几代（WtOptics，原来在镜上方那行字里，11-27 那行收了）
        local mm = MODES[st.mode]
        local NVd = OPT.NV[(st.kit and st.kit.nv) or ""] or {}
        local gen = ((mm == "whot" or mm == "bhot") and NVd.short) and ("  ·  " .. ((G.lang == "en") and NVd.short[2] or NVd.short[1])) or ""
        hintV.Text = T("drv.hintOptic", T("sight." .. mm) .. gen)
      end
      hintM.Text = T("drv.hintSmoke", vs.smoke or 0)
      hintLine.Text = T("drv.hintLine")
      if grain.Visible then
        local vs2 = cam.ViewportSize
        for _, g in ipairs(dots) do
          g.Position = UDim2.fromOffset(math.random() * vs2.X, math.random() * vs2.Y)
          g.BackgroundTransparency = 0.45 + math.random() * 0.5
        end
      end
      st.hlT -= dt
      local m = MODES[st.mode]
      if st.hlT <= 0 and (m == "whot" or m == "bhot") then
        st.hlT = 0.5
        refreshHl((m == "whot") and Color3.new(1, 1, 1) or Color3.new(0, 0, 0))
      end
    end
    -- 车长望远镜：密位刻度、估的距离、方位
    if st.binoc then
      local lv = cam.CFrame.LookVector
      local f = st.fcs
      GS.binoStep({ R = f and f.R, est = f and f.estimating, yaw = math.atan2(-lv.X, -lv.Z) })
    end
  end
end

return Drive
