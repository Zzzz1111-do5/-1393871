-- 全面大战场（客户端）——改枪界面（用户 11-20：「做一整套改枪系统，对标三角洲行动」；数据、算法在 ReplicatedStorage.GunMods）
--   部署界面选主武器那格点「改枪」进来：全屏暗底（细网格），中间是 3D 的枪（第一人称那支真 M4 / 狙击枪原模型，装着现在选的配件原模型），
--     拖动转枪、滚轮缩放；枪上每个改装位一个标签（枪口、瞄具、前握把、弹匣、战术），一根折线指到装配件的地方
--   点标签：底下一排这一位能装的配件卡片（原模型的小图、名字、主要加减、几级解锁、已装备），鼠标移上去枪上先换上、右边性能条
--     显示变化（变好的一截绿、变差的一截红，后面写 +5 / −3），点一下装上；镜头凑近那一位
--   右边「性能」：伤害、射速、有效射程、垂直 / 水平后坐力控制、操控速度、据枪稳定性、腰际射击精度、机动性（0～100 的分），
--     弹匣容量、换弹时间、瞄具倍率、枪声
--   左边：推荐改装（一键套用）、我的方案（三个，存 / 读）；顶上：改枪码（选中复制给别人，粘贴别人的点「应用」）、恢复默认、完成
--   枪械等级：标题旁 Lv 和经验条；没解锁的配件卡片上写「Lv.X 解锁」、点不了（Studio 里测试时全部解锁）
--   「完成」把这一套发给服务器（gunBuild；下次出击生效），「返回」/ Esc 不改
--   G.openGunsmith(武器, 关上以后调的函数)；G.gunModel(武器, 阵营, 配件) 给部署界面的大图用（装着配件的枪）
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local Gunsmith = {}

function Gunsmith.init(G)
  local GM = require(RS:WaitForChild("GunMods"))
  local GD = require(RS:WaitForChild("GearDefs"))
  local W0 = G.Config.Weapons
  local me = Players.LocalPlayer
  local V, CF, RGB, UD2, V2 = Vector3.new, CFrame.new, Color3.fromRGB, UDim2.new, Vector2.new
  local function T(k, ...) return G.T(k, ...) end
  local now = os.clock
  -- 配色：近黑的底、白字、黄绿强调；变好绿、变差红
  local BG, PANEL, LINE = RGB(8, 10, 12), RGB(14, 17, 20), RGB(255, 255, 255)
  local TEXT, MUTE, FAINT = RGB(236, 238, 236), RGB(150, 156, 158), RGB(90, 96, 100)
  local ACC, ACC2 = RGB(206, 255, 72), RGB(18, 22, 8)
  local UP, DOWN = RGB(108, 232, 126), RGB(255, 98, 86)
  local F_B, F_M, F_K = Enum.Font.GothamBold, Enum.Font.GothamMedium, Enum.Font.GothamBlack

  ---------------------------------------------------------------- 装着配件的枪（改枪界面、部署界面的大图）

  -- 返回 Model（器材 / 枪身骨骼坐标）、还在现生成的模型键、每一位的锚点（配件装在哪，同一坐标）
  local function gunModel(id, team, b)
    local m = Instance.new("Model")
    local wait, anchors = {}, {}
    local function need(k) if not (G.opticFailed and G.opticFailed(k)) then table.insert(wait, k) end end
    local function put(key, at, glassOK)
      local op = G.opticParts and G.opticParts(key)
      if not op then need(key) return false end
      for _, x in ipairs(op) do
        x.part.CFrame = at * x.cf
        local gt = glassOK and GM.glassT(key, x.name)
        if gt then x.part.Transparency = math.min(gt, 0.7) end
        x.part.Parent = m
      end
      return true
    end
    b = GM.clean(id, b) or {}
    if id == "m4" then
      local magIt = GM.ITEM[b.mag]
      local customMag = magIt and magIt.model and G.opticReady and G.opticReady(magIt.model)
      local base = G.m4Model and G.m4Model(customMag)
      if not base then return nil, { "m4" }, anchors end
      for _, p in ipairs(base:GetChildren()) do p.Parent = m end
      base:Destroy()
      local magCF = G.m4Track and G.m4Track("mag1") or CF(0.008, -0.252, 0.204)
      for _, slot in ipairs(GM.SLOTS) do
        local it = GM.ITEM[b[slot]]
        local M = it and it.model and G.opticMeta and G.opticMeta[it.model]
        local mt = M and GM.m4Mount(b[slot], M)
        if mt then
          local at = (mt.track == "mag") and (magCF * mt.cf) or mt.cf
          if slot ~= "mag" or customMag then put(it.model, at, true) elseif magIt.model then need(magIt.model) end
          if mt.riser then
            local rp = Instance.new("Part")
            rp.Size, rp.Color, rp.Material, rp.Anchored = V(0.058, mt.riser, 0.1), RGB(34, 34, 36), Enum.Material.Metal, true
            rp.CFrame = at * CF(0, -mt.riser / 2, 0.01)
            rp.Parent = m
          end
        end
      end
      -- 锚点：标签的折线指到这里
      local M4 = GM.M4
      local tip = GM.M4.tip
      local mz = GM.ITEM[b.muzzle]
      if mz and mz.model and G.opticMeta and G.opticMeta[mz.model] then
        local mt = GM.m4Mount(b.muzzle, G.opticMeta[mz.model])
        if mt and mt.mz then tip = mt.mz.Z - 0.08 end
      end
      anchors.muzzle = V(M4.bore[1], M4.bore[2], tip - 0.04)
      anchors.optic = V(M4.bore[1], M4.rail + 0.07, 0.26)
      anchors.grip = V(M4.bore[1], M4.under - 0.06, 0.72)
      anchors.mag = magCF * V(0, -0.05, 0)
      anchors.tac = V(M4.side + 0.03, M4.sideY, 0.74)
    else
      -- 狙击枪等：整件原模型（GearView.lua 的 G.gearModel），枪口件装在原模型的枪口
      local gm, gw = G.gearModel and G.gearModel(id, team)
      if not gm then return nil, gw and { id } or {}, anchors end
      for _, p in ipairs(gm:GetChildren()) do p.Parent = m end
      gm:Destroy()
      local key = GD.key(id, team)
      local M = key and G.opticMeta and G.opticMeta[key]
      local mz = M and GD.muzzle(M)
      if mz then
        local it = GM.ITEM[b.muzzle or ""]
        if it and it.model then put(it.model, CF(mz) * CF(0, 0, -0.03), false) end
        anchors.muzzle = mz
      end
    end
    return m, wait, anchors
  end
  G.gunModel = function(id, team, b)
    local m, wait = gunModel(id, team, b)
    return m, #wait > 0
  end

  ---------------------------------------------------------------- 界面零件

  local gui = Instance.new("ScreenGui")
  gui.Name = "Gunsmith"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 26
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")

  local function fr(parent, size, pos, color, alpha, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position = size, pos or UD2()
    f.AnchorPoint = anchor or V2()
    f.BackgroundColor3 = color or PANEL
    f.BackgroundTransparency = alpha or 0
    f.BorderSizePixel = 0
    f.Parent = parent
    return f
  end
  local function tx(parent, s, size, pos, ts, color, font, anchor, ax)
    local l = Instance.new("TextLabel")
    l.Size, l.Position = size, pos or UD2()
    l.AnchorPoint = anchor or V2()
    l.BackgroundTransparency = 1
    l.Text = s or ""
    l.TextSize = ts or 14
    l.TextColor3 = color or TEXT
    l.Font = font or F_M
    l.TextXAlignment = ax or Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Parent = parent
    return l
  end
  local function line(f, color, t, alpha)
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = color or LINE, t or 1, alpha or 0.86
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = f
    return s
  end
  local function btn(parent, s, size, pos, anchor, primary)
    local b = Instance.new("TextButton")
    b.Size, b.Position = size, pos or UD2()
    b.AnchorPoint = anchor or V2()
    b.BackgroundColor3 = primary and ACC or RGB(28, 32, 36)
    b.BackgroundTransparency = primary and 0 or 0.15
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Text = s or ""
    b.TextColor3 = primary and ACC2 or TEXT
    b.TextSize = 14
    b.Font = F_B
    b.Parent = parent
    if not primary then line(b, LINE, 1, 0.84) end
    return b
  end

  local root = fr(gui, UD2(1, 0, 1, 0), nil, BG, 0)
  root.Active = true
  do   -- 上下一点亮度变化（顶灯）、细网格
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(RGB(26, 30, 34), RGB(6, 7, 8))
    g.Rotation = 90
    g.Parent = root
    for i = 1, 40 do fr(root, UD2(0, 1, 1, 0), UD2(0, i * 64, 0, 0), LINE, 0.965) end
    for i = 1, 24 do fr(root, UD2(1, 0, 0, 1), UD2(0, 0, 0, i * 64), LINE, 0.965) end
  end
  local modal = Instance.new("TextButton")   -- 第一人称时放开鼠标（同 Garage）
  modal.Text, modal.Size, modal.BackgroundTransparency, modal.AutoButtonColor, modal.Modal = "", UDim2.fromOffset(1, 1), 1, false, true
  modal.Parent = gui
  local scaleObj = Instance.new("UIScale")   -- 按 1280×720 排的版，屏幕大小不一样按比例缩放
  scaleObj.Parent = root
  local canvas = fr(root, UD2(0, 1280, 0, 720), UD2(0.5, 0, 0.5, 0), BG, 1, V2(0.5, 0.5))

  -- 3D 枪
  local vp = Instance.new("ViewportFrame")
  vp.Name = "GunVP"
  vp.BackgroundTransparency = 1
  vp.Ambient = RGB(150, 154, 160)
  vp.LightColor = RGB(255, 250, 242)
  vp.LightDirection = V(-0.4, -1, 0.3)
  vp.Position = UD2(0, 272, 0, 120)
  vp.Size = UD2(0, 1280 - 272 - 372, 0, 720 - 120 - 196)
  vp.Parent = canvas
  local world = Instance.new("WorldModel")
  world.Parent = vp
  local vcam = Instance.new("Camera")
  vcam.FieldOfView = 30
  vcam.Parent = vp
  vp.CurrentCamera = vcam
  local overlay = fr(canvas, vp.Size, vp.Position, BG, 1)   -- 标签、折线画在这上面（和视口一样大、叠在上面，坐标一样）
  local VP_W, VP_H = 1280 - 272 - 372, 720 - 120 - 196
  local function vpSize()   -- 视口的像素大小（读不到的时候按排版的大小；测试台的 ViewportFrame 没有 AbsoluteSize）
    local ok, a = pcall(function() return vp.AbsoluteSize end)
    if ok and typeof(a) == "Vector2" and a.X > 4 and a.Y > 4 then return a end
    local sc = scaleObj and scaleObj.Scale or 1
    return V2(VP_W * sc, VP_H * sc)
  end

  -- 顶上：标题、等级
  local small = tx(canvas, "", UD2(0, 300, 0, 16), UD2(0, 40, 0, 26), 12, MUTE, F_B)
  local title = tx(canvas, "", UD2(0, 520, 0, 36), UD2(0, 40, 0, 42), 30, TEXT, F_K)
  local lvBadge = fr(canvas, UD2(0, 54, 0, 20), UD2(0, 40, 0, 84), ACC, 0)
  local lvText = tx(lvBadge, "", UD2(1, 0, 1, 0), nil, 13, ACC2, F_K, nil, Enum.TextXAlignment.Center)
  local xpBg = fr(canvas, UD2(0, 180, 0, 4), UD2(0, 104, 0, 92), LINE, 0.85)
  local xpFill = fr(xpBg, UD2(0.5, 0, 1, 0), nil, ACC, 0)
  local xpText = tx(canvas, "", UD2(0, 160, 0, 16), UD2(0, 292, 0, 86), 12, MUTE, F_M)
  local allTip = tx(canvas, "", UD2(0, 300, 0, 16), UD2(0, 40, 0, 110), 11, FAINT, F_M)
  -- 顶上右边：改枪码、恢复默认、返回、完成
  local codeLbl = tx(canvas, "", UD2(0, 70, 0, 16), UD2(0, 640, 0, 30), 11, MUTE, F_B)
  local codeBox = Instance.new("TextBox")
  codeBox.Size, codeBox.Position = UD2(0, 186, 0, 34), UD2(0, 640, 0, 48)
  codeBox.BackgroundColor3, codeBox.BackgroundTransparency, codeBox.BorderSizePixel = RGB(4, 5, 6), 0.1, 0
  codeBox.TextColor3, codeBox.TextSize, codeBox.Font = ACC, 16, Enum.Font.Code
  codeBox.ClearTextOnFocus = false
  codeBox.TextEditable = true
  codeBox.PlaceholderText = "M4A1-XXXXXX"
  codeBox.Text = ""
  codeBox.Parent = canvas
  line(codeBox, LINE, 1, 0.8)
  local codeApply = btn(canvas, "", UD2(0, 64, 0, 34), UD2(0, 832, 0, 48))
  local resetBtn = btn(canvas, "", UD2(0, 92, 0, 34), UD2(0, 902, 0, 48))
  local backBtn = btn(canvas, "", UD2(0, 92, 0, 34), UD2(0, 1000, 0, 48))
  local doneBtn = btn(canvas, "", UD2(0, 140, 0, 34), UD2(0, 1100, 0, 48), nil, true)
  local codeTip = tx(canvas, "", UD2(0, 420, 0, 14), UD2(0, 640, 0, 86), 11, FAINT, F_M)

  -- 右边：性能
  local statP = fr(canvas, UD2(0, 330, 0, 396), UD2(1, -36, 0, 120), PANEL, 0.25, V2(1, 0))
  line(statP, LINE, 1, 0.9)
  local statHead = tx(statP, "", UD2(1, -28, 0, 18), UD2(0, 14, 0, 12), 13, TEXT, F_B)
  fr(statP, UD2(0, 26, 0, 2), UD2(0, 14, 0, 34), ACC, 0)
  local ROWS = {
    { k = "dmg" }, { k = "rpm" }, { k = "range", score = true }, { k = "vrec", score = true }, { k = "hrec", score = true },
    { k = "hand", score = true }, { k = "stab", score = true }, { k = "hip", score = true }, { k = "mob", score = true },
    { k = "mag" }, { k = "reload", lower = true }, { k = "zoom", noBar = true }, { k = "sound", noBar = true },
  }
  for i, r in ipairs(ROWS) do
    local y = 44 + (i - 1) * 26
    r.lbl = tx(statP, "", UD2(0, 150, 0, 14), UD2(0, 14, 0, y), 12, MUTE, F_M)
    r.val = tx(statP, "", UD2(0, 90, 0, 14), UD2(1, -14, 0, y), 12, TEXT, F_B, V2(1, 0), Enum.TextXAlignment.Right)
    r.dt = tx(statP, "", UD2(0, 60, 0, 14), UD2(1, -106, 0, y), 12, UP, F_B, V2(1, 0), Enum.TextXAlignment.Right)
    if not r.noBar then
      r.bg = fr(statP, UD2(1, -28, 0, 3), UD2(0, 14, 0, y + 17), LINE, 0.88)
      r.fill = fr(r.bg, UD2(0.5, 0, 1, 0), nil, TEXT, 0.05)
      r.plus = fr(r.bg, UD2(0, 0, 1, 0), nil, UP, 0)
      r.minus = fr(r.bg, UD2(0, 0, 1, 0), nil, DOWN, 0)
    end
  end

  -- 左边：推荐改装、我的方案
  local leftP = fr(canvas, UD2(0, 230, 0, 384), UD2(0, 36, 0, 132), PANEL, 0.25)
  line(leftP, LINE, 1, 0.9)
  local presetHead = tx(leftP, "", UD2(1, -24, 0, 16), UD2(0, 12, 0, 12), 13, TEXT, F_B)
  fr(leftP, UD2(0, 26, 0, 2), UD2(0, 12, 0, 32), ACC, 0)
  local presetBtns = {}
  for i = 1, 5 do
    local b = btn(leftP, "", UD2(1, -24, 0, 28), UD2(0, 12, 0, 40 + (i - 1) * 33))
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextSize = 13
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 10)
    pad.Parent = b
    local lk = tx(b, "", UD2(0, 70, 1, 0), UD2(1, -8, 0, 0), 11, FAINT, F_B, V2(1, 0), Enum.TextXAlignment.Right)
    presetBtns[i] = { b = b, lk = lk }
  end
  local saveHead = tx(leftP, "", UD2(1, -24, 0, 16), UD2(0, 12, 0, 212), 13, TEXT, F_B)
  fr(leftP, UD2(0, 26, 0, 2), UD2(0, 12, 0, 232), ACC, 0)
  local saveRows = {}
  for i = 1, 3 do
    local y = 240 + (i - 1) * 46
    local b = btn(leftP, "", UD2(1, -24, 0, 40), UD2(0, 12, 0, y))
    b.Text = ""
    local nm = tx(b, "", UD2(1, -70, 0, 14), UD2(0, 10, 0, 5), 12, TEXT, F_B)
    local sm = tx(b, "", UD2(1, -20, 0, 13), UD2(0, 10, 0, 22), 10, MUTE, F_M)
    local sv = btn(b, "", UD2(0, 48, 0, 18), UD2(1, -6, 0, 4), V2(1, 0))
    sv.TextSize = 11
    saveRows[i] = { b = b, nm = nm, sm = sm, sv = sv }
  end

  -- 底下：这一位能装的配件
  local strip = fr(canvas, UD2(0, 1280 - 72, 0, 168), UD2(0.5, 0, 1, -18), PANEL, 1, V2(0.5, 1))
  local stripHead = tx(strip, "", UD2(0, 600, 0, 16), UD2(0, 0, 0, 0), 13, TEXT, F_B)
  local stripTip = tx(canvas, "", UD2(0, 500, 0, 14), UD2(1, -36, 1, -4), 10, FAINT, F_M, V2(1, 1), Enum.TextXAlignment.Right)
  local cardHolder = fr(strip, UD2(1, 0, 0, 140), UD2(0, 0, 0, 26), PANEL, 1)
  local cardLayout = Instance.new("UIListLayout")
  cardLayout.FillDirection = Enum.FillDirection.Horizontal
  cardLayout.Padding = UDim.new(0, 10)
  cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
  cardLayout.Parent = cardHolder
  local cards = {}

  ---------------------------------------------------------------- 状态

  local S = { id = nil, team = "atk", cur = nil, saved = nil, hover = nil, slot = nil, lv = 1, all = false, onDone = nil,
    model = nil, shown = nil, waitKeys = nil, anchors = {}, yaw = 0, pitch = 0.16, dist = 3.2, center = V(), tYaw = 0, tPitch = 0.16,
    tDist = 3.2, tCenter = V(), nodes = {}, cardWait = false }
  G.gunsmithOpen = function() return gui.Enabled end
  G.gunsmithDebug = function() return S, vcam, vp end   -- 测试台截图用（tools/mock/hudshot.lua kind=gunsmith）

  local function itemName(id) return T("gm.item." .. id) end
  local function curShown() -- 现在枪上画的那一套：鼠标停在某张卡片上就是换上它的
    if S.hover and S.slot then
      local b = table.clone(S.cur)
      b[S.slot] = S.hover
      return b
    end
    return S.cur
  end
  local function locked(slot, item)
    if S.all then return false end
    local lv = GM.unlockLv(S.id, slot, item)
    return lv ~= nil and lv > S.lv
  end

  ---------------------------------------------------------------- 3D：装模型、镜头

  local function boundsOf(m)
    local mn, mx = V(1e9, 1e9, 1e9), V(-1e9, -1e9, -1e9)
    for _, p in ipairs(m:GetDescendants()) do
      if p:IsA("BasePart") then
        local c, h = p.CFrame, p.Size / 2
        for sx = -1, 1, 2 do
          for sy = -1, 1, 2 do
            for sz = -1, 1, 2 do
              local w = c * V(sx * h.X, sy * h.Y, sz * h.Z)
              mn = V(math.min(mn.X, w.X), math.min(mn.Y, w.Y), math.min(mn.Z, w.Z))
              mx = V(math.max(mx.X, w.X), math.max(mx.Y, w.Y), math.max(mx.Z, w.Z))
            end
          end
        end
      end
    end
    return mn, mx
  end
  local home = { center = V(0, -0.05, 0.3), dist = 3.2 }
  local function rebuild(force)
    local b = curShown()
    local code = GM.encode(b)
    if not force and S.shown == code and not S.waitKeys then return end
    S.shown = code
    if S.model then S.model:Destroy() S.model = nil end
    local m, wait, anchors = gunModel(S.id, S.team, b)
    S.waitKeys = (wait and #wait > 0) and wait or nil
    S.anchors = anchors or {}
    if m then
      m.Parent = world
      S.model = m
      if force then   -- 换了枪：按枪的大小定镜头
        local mn, mx = boundsOf(m)
        local size = mx - mn
        home.center = (mn + mx) / 2
        local abs = vpSize()
        local aspect = (abs.X > 4 and abs.Y > 4) and (abs.X / abs.Y) or 1.6
        local tv = math.tan(math.rad(vcam.FieldOfView) / 2)
        home.dist = math.max(size.Z / 2 / (tv * aspect), size.Y / 2 / tv) * 1.3 + size.X / 2   -- 两头留出标签的地方
        S.tCenter, S.tDist = home.center, home.dist
        S.center, S.dist = home.center, home.dist
      end
    end
  end

  -- 镜头：从枪的左侧（+X，配件都在这边）略靠前、略高看过去；选了某一位就凑近它
  local function camCF()
    local cp = math.cos(S.pitch)
    local dir = V(cp * math.sin(S.yaw), math.sin(S.pitch), cp * math.cos(S.yaw))
    return CFrame.lookAt(S.center + dir * S.dist, S.center)
  end
  local YAW0 = math.pi / 2 - 0.18
  local function focus(slot)
    local a = slot and S.anchors[slot]
    if a then
      S.tCenter = home.center:Lerp(a, 0.3)
      S.tDist = home.dist * 0.88
    else
      S.tCenter, S.tDist = home.center, home.dist
    end
  end
  -- 世界坐标 → 视口里的像素
  local function project(p)
    local cc = vcam.CFrame
    local l = cc:PointToObjectSpace(p)
    if l.Z > -0.01 then return nil end
    local abs = vpSize()
    local sc = scaleObj.Scale > 0 and scaleObj.Scale or 1
    local w, h = abs.X / sc, abs.Y / sc   -- 画在缩放后的坐标里
    local tv = math.tan(math.rad(vcam.FieldOfView) / 2)
    local aspect = w / math.max(1, h)
    local nx, ny = l.X / (-l.Z * tv * aspect), l.Y / (-l.Z * tv)
    return V2(w / 2 + nx * w / 2, h / 2 - ny * h / 2)
  end

  ---------------------------------------------------------------- 改装位标签

  local NODE_W, NODE_H = 136, 40
  local function node(slot)
    local n = S.nodes[slot]
    if n then return n end
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(NODE_W, NODE_H)
    b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel, b.AutoButtonColor, b.Text = PANEL, 0.12, 0, false, ""
    b.ZIndex = 3
    b.Parent = overlay
    local st = line(b, LINE, 1, 0.8)
    local bar = fr(b, UD2(0, 3, 1, 0), nil, ACC, 0)
    bar.ZIndex = 3
    local sl = tx(b, "", UD2(1, -14, 0, 12), UD2(0, 10, 0, 5), 10, MUTE, F_B)
    local it = tx(b, "", UD2(1, -14, 0, 16), UD2(0, 10, 0, 19), 12, TEXT, F_B)
    sl.ZIndex, it.ZIndex = 3, 3
    local lv = fr(overlay, UD2(0, 1, 0, 1), nil, LINE, 0.45)   -- 竖线
    local lh = fr(overlay, UD2(0, 1, 0, 1), nil, LINE, 0.45)   -- 横线
    local dot = fr(overlay, UD2(0, 6, 0, 6), nil, ACC, 0, V2(0.5, 0.5))
    lv.ZIndex, lh.ZIndex, dot.ZIndex = 2, 2, 3
    n = { b = b, st = st, bar = bar, sl = sl, it = it, lv = lv, lh = lh, dot = dot, slot = slot }
    b.MouseButton1Click:Connect(function()
      if S.slot == slot then S.slot = nil else S.slot = slot end
      S.hover = nil
      focus(S.slot)
      G.gunsmithRefresh()
    end)
    S.nodes[slot] = n
    return n
  end
  local TOP = { muzzle = true, optic = true, tac = true }   -- 标签放在枪上面的几位（别的在下面）
  local function layoutNodes()
    local D = GM.DEF[S.id]
    local rows = { top = {}, bot = {} }
    for _, slot in ipairs(GM.SLOTS) do
      local n = S.nodes[slot]
      local a = D and D.slots[slot] and S.anchors[slot]
      local p = a and project(a)
      if n then n.b.Visible, n.lv.Visible, n.lh.Visible, n.dot.Visible = p ~= nil, p ~= nil, p ~= nil, p ~= nil end
      if p and n then table.insert(TOP[slot] and rows.top or rows.bot, { n = n, p = p, x = p.X }) end
    end
    local abs = vpSize()
    local sc = scaleObj.Scale > 0 and scaleObj.Scale or 1
    local w, h = abs.X / sc, abs.Y / sc
    for rk, list in pairs(rows) do
      table.sort(list, function(a, b) return a.x < b.x end)
      -- 一行里不叠：从左往右推开，再整体挪回框里
      for i, e in ipairs(list) do
        e.x = math.clamp(e.x, NODE_W / 2 + 4, w - NODE_W / 2 - 4)
        if i > 1 then e.x = math.max(e.x, list[i - 1].x + NODE_W + 12) end
      end
      local over = (#list > 0) and (list[#list].x - (w - NODE_W / 2 - 4)) or 0
      if over > 0 then for _, e in ipairs(list) do e.x -= over end end
      for _, e in ipairs(list) do
        local n, p = e.n, e.p
        local top = rk == "top"
        local ny = top and math.max(8, p.Y - 96) or math.min(h - NODE_H - 8, p.Y + 70)
        n.b.Position = UDim2.fromOffset(e.x - NODE_W / 2, ny)
        local edge = top and (ny + NODE_H) or ny   -- 折线接在标签靠枪的那条边
        n.dot.Position = UDim2.fromOffset(p.X, p.Y)
        local y0, y1 = math.min(p.Y, edge), math.max(p.Y, edge)
        n.lv.Position, n.lv.Size = UDim2.fromOffset(p.X, y0), UDim2.fromOffset(1, math.max(1, y1 - y0))
        local x0, x1 = math.min(p.X, e.x), math.max(p.X, e.x)
        n.lh.Position, n.lh.Size = UDim2.fromOffset(x0, edge), UDim2.fromOffset(math.max(1, x1 - x0), 1)
      end
    end
  end

  ---------------------------------------------------------------- 数字

  -- 一套配件 → 每一行的数（分 / 物理量）
  local function statsOf(b)
    local w = GM.apply(S.id, W0[S.id], b)
    local s = GM.score(S.id, b)
    return {
      dmg = { v = w.dmg or 0, bar = (w.dmg or 0) / 100, t = tostring(w.dmg or 0) },
      rpm = { v = 60 / (w.rate or 1), bar = (60 / (w.rate or 1)) / 900, t = T("gm.rpm", math.floor(60 / (w.rate or 1) + 0.5)) },
      range = { v = s.range, bar = s.range / 100, t = T("gm.m", GM.effRange(w)) },
      vrec = { v = s.vrec, bar = s.vrec / 100, t = tostring(math.floor(s.vrec + 0.5)) },
      hrec = { v = s.hrec, bar = s.hrec / 100, t = tostring(math.floor(s.hrec + 0.5)) },
      hand = { v = s.hand, bar = s.hand / 100, t = tostring(math.floor(s.hand + 0.5)) },
      stab = { v = s.stab, bar = s.stab / 100, t = tostring(math.floor(s.stab + 0.5)) },
      hip = { v = s.hip, bar = s.hip / 100, t = tostring(math.floor(s.hip + 0.5)) },
      mob = { v = s.mob, bar = s.mob / 100, t = tostring(math.floor(s.mob + 0.5)) },
      mag = { v = w.mag or 0, bar = (w.mag or 0) / 60, t = T("gm.rounds", w.mag or 0) },
      reload = { v = w.reload or 0, bar = math.clamp(1 - ((w.reload or 2) - 1.4) / 3, 0.05, 1), t = T("gm.sec", string.format("%.1f", w.reload or 0)) },
      zoom = { v = w.scope or w.adsZoom or 1, t = T("gm.x", string.format("%.1f", w.scope or w.adsZoom or 1)) },
      sound = { v = w.quiet and 1 or 0, t = w.quiet and T("gm.quiet") or T("gm.loud") },
    }
  end
  local function fmtD(d, k)
    if math.abs(d) < 0.05 then return "" end
    if k == "reload" then return string.format("%+.1f", d) end
    local n = math.floor(d + 0.5)   -- 四舍五入（负数也是：-12 还是 -12）
    if n == 0 then return "" end
    return string.format("%+d", n)
  end
  local function drawStats()
    local A = statsOf(S.cur)
    local B = (S.hover and S.slot) and statsOf(curShown()) or A
    for _, r in ipairs(ROWS) do
      local a, b = A[r.k], B[r.k]
      r.lbl.Text = T("gm.st." .. r.k)
      r.val.Text = b.t
      local d = (b.v or 0) - (a.v or 0)
      local good = (r.lower and d < 0) or (not r.lower and d > 0)
      if r.k == "sound" or r.k == "zoom" then
        r.dt.Text = ""
        r.val.TextColor3 = (b.v ~= a.v) and ACC or TEXT
      else
        r.dt.Text = fmtD(d, r.k)
        r.dt.TextColor3 = good and UP or DOWN
        r.val.TextColor3 = TEXT
      end
      if r.bg then
        local fa, fb = math.clamp(a.bar, 0, 1), math.clamp(b.bar, 0, 1)
        r.fill.Size = UD2(math.min(fa, fb), 0, 1, 0)
        local up, dn = fb > fa, fb < fa
        r.plus.Visible, r.minus.Visible = up, dn
        if up then
          r.plus.Position, r.plus.Size = UD2(fa, 0, 0, 0), UD2(fb - fa, 0, 1, 0)
          r.plus.BackgroundColor3 = r.lower and DOWN or UP
        elseif dn then
          r.minus.Position, r.minus.Size = UD2(fb, 0, 0, 0), UD2(fa - fb, 0, 1, 0)
          r.minus.BackgroundColor3 = r.lower and UP or DOWN
        end
      end
    end
  end

  -- 配件主要的加减（卡片上写两三项）
  local SHORT = { vrec = "gm.sh.vrec", hrec = "gm.sh.hrec", hand = "gm.sh.hand", stab = "gm.sh.stab", hip = "gm.sh.hip", range = "gm.sh.range", mob = "gm.sh.mob" }
  local function tagsOf(item)
    local it = GM.ITEM[item]
    local parts = {}
    if it and it.mag and S.id == "m4" then table.insert(parts, string.format('<font color="#E6E8E6">%s</font>', T("gm.rounds", it.mag))) end
    if it and it.quiet then table.insert(parts, string.format('<font color="#CEFF48">%s</font>', T("gm.quiet"))) end
    if it and it.zoom and it.scope then table.insert(parts, string.format('<font color="#E6E8E6">%s</font>', T("gm.x", it.zoom))) end
    local list = {}
    for k, v in pairs((it and it.st) or {}) do table.insert(list, { k = k, v = v }) end
    table.sort(list, function(a, b) return math.abs(a.v) > math.abs(b.v) end)
    for i = 1, math.min(3, #list) do
      local e = list[i]
      table.insert(parts, string.format('<font color="%s">%s %+d</font>', e.v > 0 and "#6CE87E" or "#FF6256", T(SHORT[e.k]), e.v))
    end
    return table.concat(parts, "  ")
  end

  ---------------------------------------------------------------- 配件卡片

  local CARD_W, CARD_H = 158, 136
  local function clearCards()
    for _, c in ipairs(cards) do c.b:Destroy() end
    cards = {}
  end
  local function cardModel(c)
    local it = GM.ITEM[c.item]
    if not it or not it.model then return true end
    local op = G.opticParts and G.opticParts(it.model)
    if not op then return G.opticFailed and G.opticFailed(it.model) end
    local m = Instance.new("Model")
    for _, x in ipairs(op) do
      x.part.CFrame = x.cf
      local gt = GM.glassT(it.model, x.name)
      if gt then x.part.Transparency = math.min(gt, 0.7) end
      x.part.Parent = m
    end
    if G.viewFit then G.viewFit(c.vp, m, 1.15, V(-1, -0.3, 0.35).Unit) end   -- 从左后上方看过去（配件的侧面）
    return true
  end
  local function buildCards()
    clearCards()
    local D = GM.DEF[S.id]
    local list = S.slot and D and D.slots[S.slot] or {}
    for i, x in ipairs(list) do
      local item = x[1]
      local b = Instance.new("TextButton")
      b.Size = UDim2.fromOffset(CARD_W, CARD_H)
      b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel, b.AutoButtonColor, b.Text = PANEL, 0.1, 0, false, ""
      b.LayoutOrder = i
      b.Parent = cardHolder
      local st = line(b, LINE, 1, 0.84)
      local v = Instance.new("ViewportFrame")
      v.BackgroundTransparency = 1
      v.Size, v.Position = UD2(1, -16, 0, 66), UD2(0, 8, 0, 6)
      v.Ambient, v.LightColor, v.LightDirection = RGB(150, 154, 160), RGB(255, 250, 242), V(-0.4, -1, 0.3)
      v.Parent = b
      local stock = not (GM.ITEM[item] and GM.ITEM[item].model)
      local none = tx(b, stock and T((item == "grip_none" or item == "tac_none") and "gm.none" or "gm.stock") or "", UD2(1, 0, 0, 66), UD2(0, 0, 0, 6), 12, FAINT, F_B, nil, Enum.TextXAlignment.Center)
      local nm = tx(b, itemName(item), UD2(1, -16, 0, 16), UD2(0, 8, 0, 76), 13, TEXT, F_B)
      local tg = tx(b, tagsOf(item), UD2(1, -16, 0, 30), UD2(0, 8, 0, 96), 11, MUTE, F_M)
      tg.RichText, tg.TextWrapped, tg.TextTruncate = true, true, Enum.TextTruncate.None
      tg.TextYAlignment = Enum.TextYAlignment.Top
      local eq = fr(b, UD2(0, 50, 0, 16), UD2(1, -6, 0, 6), ACC, 0, V2(1, 0))
      local eqT = tx(eq, T("gm.equipped"), UD2(1, 0, 1, 0), nil, 10, ACC2, F_K, nil, Enum.TextXAlignment.Center)
      local lk = fr(b, UD2(1, 0, 1, 0), nil, RGB(0, 0, 0), 0.35)
      local lkT = tx(lk, T("gm.lock", x[2]), UD2(1, 0, 0, 20), UD2(0, 0, 0.5, -10), 13, TEXT, F_B, nil, Enum.TextXAlignment.Center)
      local c = { b = b, st = st, vp = v, item = item, eq = eq, eqT = eqT, lk = lk, lkT = lkT, none = none, nm = nm, ready = stock }
      c.ready = cardModel(c)
      b.MouseEnter:Connect(function()
        if not gui.Enabled then return end
        S.hover = item
        G.gunsmithRefresh(true)
      end)
      b.MouseLeave:Connect(function()
        if S.hover == item then
          S.hover = nil
          G.gunsmithRefresh(true)
        end
      end)
      b.MouseButton1Click:Connect(function()
        if locked(S.slot, item) then
          G.toast(T("gm.lock", x[2]), "bad")
          return
        end
        S.cur[S.slot] = item
        S.hover = nil
        if G.playSound then G.playSound("quiet", nil, 1.6) end
        G.gunsmithRefresh()
      end)
      table.insert(cards, c)
    end
    S.cardWait = false
    for _, c in ipairs(cards) do if not c.ready then S.cardWait = true end end
  end
  local function drawCards()
    for _, c in ipairs(cards) do
      local on = S.cur[S.slot] == c.item
      local lk = locked(S.slot, c.item)
      c.eq.Visible = on
      c.lk.Visible = lk
      c.st.Color = on and ACC or LINE
      c.st.Transparency = on and 0.1 or ((S.hover == c.item) and 0.5 or 0.84)
      c.b.BackgroundColor3 = (S.hover == c.item) and RGB(26, 30, 34) or PANEL
    end
  end

  ---------------------------------------------------------------- 刷新

  local cardsFor = nil   -- 卡片现在是哪把枪、哪一位的
  local function presetLocked(b)
    local n = 0
    for _, slot in ipairs(GM.SLOTS) do
      if b[slot] and locked(slot, b[slot]) then n += 1 end
    end
    return n
  end
  local function saveList()
    local s = me:GetAttribute("GunSaves_" .. S.id) or ""
    local out = {}
    local i = 1
    for part in string.gmatch(s .. "|", "([^|]*)|") do
      out[i] = part
      i += 1
    end
    return out
  end
  local function summary(b)
    local names = {}
    for _, slot in ipairs(GM.SLOTS) do
      local it = b[slot] and GM.ITEM[b[slot]]
      if it and it.model then table.insert(names, itemName(b[slot])) end
    end
    return (#names > 0) and table.concat(names, " · ") or T("gm.stock")
  end

  function G.gunsmithRefresh(light)
    if not gui.Enabled or not S.id then return end
    rebuild(false)
    drawStats()
    drawCards()
    if light then return end
    local D = GM.DEF[S.id]
    small.Text = T("gm.title") .. "  ·  GUNSMITH"
    title.Text = T("weapon." .. S.id)
    local xp = me:GetAttribute("GunXp_" .. S.id) or 0
    local lv, a, nx = GM.level(S.id, xp)
    S.lv = lv
    lvText.Text = T("gm.lv", lv)
    if nx then
      xpFill.Size = UD2(math.clamp((xp - a) / math.max(1, nx - a), 0, 1), 0, 1, 0)
      xpText.Text = T("gm.xp", xp, nx)
    else
      xpFill.Size = UD2(1, 0, 1, 0)
      xpText.Text = T("gm.max")
    end
    allTip.Text = S.all and T("gm.allOpen") or ""
    codeLbl.Text = T("gm.code")
    codeTip.Text = T("gm.codeTip")
    if not codeBox:IsFocused() then codeBox.Text = GM.code(S.id, S.cur) or "" end
    codeApply.Text = T("gm.apply")
    resetBtn.Text = T("gm.reset")
    backBtn.Text = T("gm.back")
    doneBtn.Text = T("gm.done")
    statHead.Text = T("gm.stats")
    presetHead.Text = T("gm.presets")
    saveHead.Text = T("gm.saves")
    for i, pb in ipairs(presetBtns) do
      local p = D.presets[i]
      pb.b.Visible = p ~= nil
      if p then
        pb.b.Text = T("gm.preset." .. p.id)
        local n = presetLocked(p.b)
        pb.lk.Text = (n > 0) and T("gm.nLocked", n) or ""
      end
    end
    local saves = saveList()
    for i, r in ipairs(saveRows) do
      local code = saves[i] or ""
      r.nm.Text = T("gm.slotN", i)
      r.sm.Text = (code ~= "") and summary(GM.clean(S.id, GM.decode(code))) or T("gm.empty")
      r.sm.TextColor3 = (code ~= "") and MUTE or FAINT
      r.sv.Text = T("gm.saveBtn")
    end
    -- 改装位标签
    for _, slot in ipairs(GM.SLOTS) do
      local has = D.slots[slot] ~= nil
      local n = has and node(slot) or S.nodes[slot]
      if n then
        n.b.Visible = has
        if has then
          n.sl.Text = T("gm.slot." .. slot)
          n.it.Text = itemName(S.cur[slot])
          local on = S.slot == slot
          n.st.Color = on and ACC or LINE
          n.st.Transparency = on and 0.05 or 0.8
          n.bar.BackgroundColor3 = on and ACC or ((GM.ITEM[S.cur[slot]] and GM.ITEM[S.cur[slot]].model) and TEXT or FAINT)
        end
      end
    end
    -- 底下的卡片
    local key = S.id .. ":" .. tostring(S.slot)
    if cardsFor ~= key then
      cardsFor = key
      buildCards()
    end
    stripHead.Text = S.slot and (T("gm.slot." .. S.slot) .. "  ·  " .. #(D.slots[S.slot] or {})) or T("gm.pickSlot")
    stripTip.Text = T("gm.tip")
    drawCards()
  end

  ---------------------------------------------------------------- 按钮

  local function close(commit)
    if not gui.Enabled then return end
    if commit and S.id then
      local changed = GM.encode(S.cur) ~= GM.encode(S.saved)
      if changed then
        pcall(function() G.R.Act:FireServer("gunBuild", S.id, S.cur) end)
        if G.S and G.S.alive then G.toast(T("gm.nextSpawn"), "info") end
      end
    end
    gui.Enabled = false
    if S.model then S.model:Destroy() S.model = nil end
    clearCards()
    cardsFor = nil
    local f = S.onDone
    S.onDone = nil
    if f then task.defer(f, commit and S.cur or nil) end
  end
  doneBtn.Activated:Connect(function() close(true) end)
  backBtn.Activated:Connect(function() close(false) end)
  resetBtn.Activated:Connect(function()
    S.cur = GM.default(S.id)
    S.hover = nil
    G.gunsmithRefresh()
  end)
  local function applyBuild(b)
    local n = 0
    local out = table.clone(S.cur)
    for _, slot in ipairs(GM.SLOTS) do
      if b[slot] and GM.DEF[S.id].slots[slot] then
        if locked(slot, b[slot]) then n += 1 else out[slot] = b[slot] end
      end
    end
    S.cur = GM.clean(S.id, out)
    S.hover = nil
    if n > 0 then G.toast(T("gm.someLocked", n), "bad") end
    G.gunsmithRefresh()
    return n
  end
  for i, pb in ipairs(presetBtns) do
    pb.b.Activated:Connect(function()
      local p = GM.DEF[S.id].presets[i]
      if p then applyBuild(p.b) end
    end)
  end
  for i, r in ipairs(saveRows) do
    r.b.Activated:Connect(function()
      local code = saveList()[i] or ""
      if code ~= "" then applyBuild(GM.decode(code)) end
    end)
    r.sv.Activated:Connect(function()
      pcall(function() G.R.Act:FireServer("gunSave", S.id, i, S.cur) end)
      G.toast(T("gm.saved", i), "good")
      task.delay(0.5, function() G.gunsmithRefresh() end)   -- 服务器写好属性再刷
    end)
  end
  codeApply.Activated:Connect(function()
    local id, b, why = GM.parse(codeBox.Text)
    if not id then
      G.toast(T((why == "sum") and "gm.codeSum" or ((why == "gun") and "gm.codeGun" or "gm.codeBad")), "bad")
      return
    end
    if id ~= S.id then G.toast(T("gm.codeGun"), "bad") return end
    if applyBuild(b) == 0 then G.toast(T("gm.codeOk"), "good") end
  end)

  ---------------------------------------------------------------- 拖动转枪、滚轮缩放

  local drag = nil
  vp.InputBegan:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
      drag = { p = io.Position, yaw = S.tYaw, pitch = S.tPitch }
    end
  end)
  UIS.InputChanged:Connect(function(io)
    if not gui.Enabled then return end
    if drag and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
      local d = io.Position - drag.p
      S.tYaw = drag.yaw - d.X * 0.008
      S.tPitch = math.clamp(drag.pitch + d.Y * 0.006, -0.9, 1.1)
    elseif io.UserInputType == Enum.UserInputType.MouseWheel then
      S.tDist = math.clamp(S.tDist * (io.Position.Z > 0 and 0.88 or 1.14), home.dist * 0.3, home.dist * 1.6)
    end
  end)
  UIS.InputEnded:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then drag = nil end
  end)
  UIS.InputBegan:Connect(function(io, gp)
    if not gui.Enabled or gp then return end
    if io.KeyCode == Enum.KeyCode.Escape then close(false)
    elseif io.KeyCode == Enum.KeyCode.Return then close(true)
    elseif io.KeyCode == Enum.KeyCode.R then   -- 镜头回正
      S.tYaw, S.tPitch = YAW0, 0.16
      S.slot = nil
      focus(nil)
      G.gunsmithRefresh()
    end
  end)

  ---------------------------------------------------------------- 每帧

  local pollT = 0
  G.frameConn("Gunsmith", function(dt)
    if not gui.Enabled then return end
    local vs = workspace.CurrentCamera.ViewportSize
    scaleObj.Scale = math.clamp(math.min(vs.X / 1280, vs.Y / 720), 0.5, 1.6)
    local k = math.min(1, dt * 9)
    S.yaw += (S.tYaw - S.yaw) * k
    S.pitch += (S.tPitch - S.pitch) * k
    S.dist += (S.tDist - S.dist) * k
    S.center = S.center:Lerp(S.tCenter, k)
    vcam.CFrame = camCF()
    layoutNodes()
    -- 配件模型还在现生成：好了就重新装 / 补上卡片的小图
    local t = now()
    if t - pollT > 0.4 then
      pollT = t
      if S.waitKeys then
        local ok = true
        for _, key in ipairs(S.waitKeys) do
          if not (G.opticReady and G.opticReady(key)) and not (G.opticFailed and G.opticFailed(key)) and key ~= "m4" and key ~= S.id then ok = false end
        end
        if ok or (S.waitKeys[1] == "m4" and G.m4Model and G.m4Model()) then rebuild(true) end
      end
      if S.cardWait then
        S.cardWait = false
        for _, c in ipairs(cards) do
          if not c.ready then
            c.ready = cardModel(c)
            if not c.ready then S.cardWait = true end
          end
        end
      end
    end
  end)

  ---------------------------------------------------------------- 打开

  function G.openGunsmith(id, onDone)
    if not GM.has(id) then return false end
    S.id = id
    S.team = (G.S and G.S.team) or me:GetAttribute("Side") or "atk"
    S.saved = G.myBuild and G.myBuild(id) or GM.default(id)
    S.cur = table.clone(S.saved)
    S.hover, S.slot = nil, nil
    S.all = me:GetAttribute("GunAll") == true
    S.onDone = onDone
    S.yaw, S.pitch, S.tYaw, S.tPitch = YAW0, 0.16, YAW0, 0.16
    cardsFor = nil
    for _, n in pairs(S.nodes) do n.b.Visible = false end
    gui.Enabled = true
    -- 这把枪的配件模型都先排队现生成（卡片的小图、换上去都要）
    for _, slot in ipairs(GM.SLOTS) do
      for _, x in ipairs((GM.DEF[id].slots[slot]) or {}) do
        local it = GM.ITEM[x[1]]
        if it and it.model and G.opticReady and not G.opticReady(it.model) and G.opticParts then G.opticParts(it.model) end
      end
    end
    task.defer(function()
      rebuild(true)
      G.gunsmithRefresh()
    end)
    return true
  end
  -- 等级、方案、存好的配件变了（服务器写属性）：开着就刷新
  for _, a in ipairs({ "GunXp_m4", "GunXp_sniper", "GunSaves_m4", "GunSaves_sniper", "GunAll" }) do
    pcall(function()
      me:GetAttributeChangedSignal(a):Connect(function()
        if gui.Enabled then
          S.all = me:GetAttribute("GunAll") == true
          G.gunsmithRefresh()
        end
      end)
    end)
  end
end

return Gunsmith
