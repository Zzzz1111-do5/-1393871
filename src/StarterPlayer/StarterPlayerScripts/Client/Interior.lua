-- Roblox全面大战场（客户端）——载具内饰：车里按真实布局拼出来的乘员舱，坐在乘员位上看（对标 Steel Beasts），也能拿来拍电影
--   用户 11-21：所有载具一比一还原内饰和里面所有功能性的东西（屏幕等），全部看 Steel Beasts，每个坦克现实中的内部结构；要拿去拍电影
--   按键（开坦克时）：F2 驾驶员、F3 炮长、F4 车长、F5 装填手（车外按就进车内那个位）；车里 C 换下一个乘员位、最后回车外（11-27 起车外的 C 是望远镜）；炮长位上 Shift 进主瞄准镜；
--     B 导演镜头（跟着车走的自由镜头：方向键前后左右、PageUp / PageDown 上下、Ctrl 慢、鼠标转、滚轮变焦）；L 车内灯（白 → 蓝绿 → 红 → 关）；
--     U 藏起全部界面（拍片）；滚轮在乘员位上是变焦
--   · 内饰零件只在镜头在车里时才放进场景、每帧按车体 / 炮塔 / 炮的姿态一次 BulkMoveTo（View.lua 算好的 v.hullF、v.tF）
--   · 车里四个乘员：R15 小人，骨盆放在座位上、手握在操纵杆 / 方向把上、脚踩踏板（反向运动学）；自己坐的那个位置不画头（第一人称看得见自己的手）
--   · 会动的：炮塔篮跟着炮塔转、炮闩跟着炮俯仰；开炮炮闩后坐（真实行程）、立楔式炮闩落下；装填手转身、膝盖顶开弹药舱门、抽出炮弹、
--     转回来推进炮膛、关闩、拨到「待发」，喊 UP——整个过程按这门炮的装填时间走；弹架上的炮弹按剩下的弹数少下去；
--     炮长的双握把跟着炮塔转、炮俯仰的速度摆；驾驶员的 T 形把跟着方向转；屏幕全是实时数据
--   · 开炮：观察镜里透进来一下火光、车里扬尘、镜头一震；挨打：灯闪、红色告警灯、火星和烟、镜头猛震
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Interior = {}

function Interior.init(G)
  local Kit = require(script.Parent:WaitForChild("InteriorKit"))
local Cav = require(script.Parent:WaitForChild("InteriorCav"))   -- 从原车挖出来的内腔（CavityMeta）
  local Defs = require(script.Parent:WaitForChild("InteriorDefs"))
  local Screens = require(script.Parent:WaitForChild("InteriorScreens"))
  local VD = require(RS:WaitForChild("VehDefs"))
  local AM = require(script.Parent:WaitForChild("AirModels"))
  local V, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
  local RGB = Color3.fromRGB
  local S = Kit.S
  local rad = math.rad
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
  local function sm(t) t = clamp(t, 0, 1) return t * t * (3 - 2 * t) end
  local function T(zh, en) return (G.lang == "en") and en or zh end

  -- 真模型部件（Sketchfab CC-BY 原模型，Optics.lua：导入的 GLB 或开局后台现生成的网格）：电台、灭火瓶、120 / 125 毫米弹、乘员头盔
  Kit.props = function(key) return G.opticParts and G.opticParts(key) or nil end
  local IP_KEYS = { "ip_m829", "ip_m829lo", "ip_r125", "ip_he125", "ip_chg125", "ip_ext", "ip_radio", "ip_radio2", "ip_cvc", "ip_tsh",
    "ip_cdu", "ip_cdus", "ip_yoke", "ip_stick", "ip_asq2", "ip_sw", "ip_lamp", "ip_can",   -- 这八件：照用户发来的 M1A2 车长位照片、插图、钢铁猛兽截图找的 / 做的显示器、握把、电子箱、开关面板、顶灯、弹箱
    "ip_dseat", "ip_swheel", "ip_lever", "ip_gauges", "ip_pedals", "ip_grip" }   -- 用户 11-23「很粗糙…不要自己建模 然后用 blender」：座椅、方向盘、操纵杆、仪表、踏板、握把（tools/weapons/blprep.py）
  local prewarmed = false

  -- 车里画不画乘员小人：用户 11-22 晚「驾驶室不要显示人了」关过；11-24「坦克要有精细的 roblox 人物有不同的动画来负责干不同的活
  --   玩家第一人称就是负责扮演炮手视角」——地面车又画上（Roblox 小人，InteriorKit K.crew），飞机座舱照旧不画
  local SHOW_CREW = true
  G.interiorShowCrew = function(on) SHOW_CREW = on == true end   -- 测试、拍片用

  -- 型号 → 内饰（没有专门做的先用最接近的同类车）
  -- M1A1 / M1A2：M1A1 原模型自带的炮塔内饰（InteriorAbrams.lua：没导入拆好的 m1a1i 就照旧零件拼的）；M10 布克借零件拼的 M1A2（四人、手动装填）
  local ALIAS = { m1a2 = "m1a2", m1a1 = "m1a1", ztz99a = "ztz99a", ztz96 = "ztz99a", t90m = "ztz99a" }
  G.interiorDefs = Defs   -- 测试用

  local cur = nil          -- 正在用的内饰：{ key, id, b, spec, model, crew, ... }
  local mode = nil         -- nil 车外 / "seat" 乘员位 / "free" 导演镜头
  local station = nil      -- 现在坐的位置
  local lastStation = {}   -- 每型车上次坐的位置
  local lightMode = 1      -- 1 白、2 蓝绿、3 红、4 关
  local LIGHTS = { RGB(255, 244, 228), RGB(120, 230, 210), RGB(255, 70, 50), RGB(0, 0, 0) }
  local LIGHTK = { 1, 0.8, 0.7, 0 }
  local hideUI = false
  local quickOptic = false   -- T：车外直接进车长主观瞄（建好内饰那一帧开镜）
  local look = { yaw = 0, pitch = 0, fov = 72, fovT = 72 }
  local free = { p = V(), yaw = 0, pitch = 0 }
  local shake = 0
  local stepScope, actions   -- 开镜动画、按键的功能（下面定义）
  local optic, exitOptic, stepOptic, enterOptic   -- 别的观瞄设备（下面定义）
  local stepAir, scratches   -- 飞机座舱、玻璃划痕（下面定义）
  local glintList = {}         -- 带划痕的玻璃（划痕反光，stepGlints）：拆内饰时清掉
  local scopePhase = function() return false end

  ---------------------------------------------------------------- 提示条

  local gui = Instance.new("ScreenGui")
  gui.Name = "Interior"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 6
  gui.Parent = me:WaitForChild("PlayerGui")
  local hint = Instance.new("TextLabel")
  hint.AnchorPoint = Vector2.new(0.5, 1)
  hint.Position = UDim2.new(0.5, 0, 1, -10)
  hint.Size = UDim2.new(0.9, 0, 0, 22)
  hint.BackgroundTransparency = 1
  hint.TextColor3 = RGB(230, 236, 230)
  hint.TextStrokeTransparency = 0.4
  hint.Font = Enum.Font.BuilderSansMedium
  hint.TextSize = 14
  hint.Visible = false
  hint.Parent = gui
  local title = Instance.new("TextLabel")
  title.AnchorPoint = Vector2.new(0.5, 0)
  title.Position = UDim2.new(0.5, 0, 0, 14)
  title.Size = UDim2.new(0.6, 0, 0, 24)
  title.BackgroundTransparency = 1
  title.TextColor3 = RGB(255, 236, 190)
  title.TextStrokeTransparency = 0.4
  title.Font = Enum.Font.BuilderSansBold
  title.TextSize = 18
  title.Visible = false
  title.Parent = gui
  local NAMES = {
    driver = { "驾驶员", "DRIVER" }, gunner = { "炮长", "GUNNER" }, commander = { "车长", "COMMANDER" }, loader = { "装填手", "LOADER" },
    pilot = { "飞行员", "PILOT" }, wso = { "武器官", "WSO" }, cpg = { "副驾驶 / 射手", "CPG" },
    copilot = { "副驾驶", "COPILOT" }, troop = { "载员", "TROOP" },
  }
  local function stationName(k) local n = NAMES[k] return n and T(n[1], n[2]) or tostring(k) end

  -- 拍片：把所有界面（除了 SurfaceGui 的屏幕，那是车里的东西）藏起来 / 放回来
  local hidden = {}
  local function setHideUI(on)
    hideUI = on
    local pg = me:FindFirstChild("PlayerGui")
    if not pg then return end
    if on then
      for _, g in ipairs(pg:GetChildren()) do   -- 光学效果（开镜的光圈、瞄准镜画面、座舱盖眩光：属性 Fx）不算界面，照样画
        if g:IsA("ScreenGui") and g.Enabled and not g:GetAttribute("Fx") then hidden[g] = true g.Enabled = false end
      end
    else
      for g in pairs(hidden) do if g.Parent then g.Enabled = true end end
      hidden = {}
    end
    pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, not on) end)
  end
  G.interiorHideUI = setHideUI

  ---------------------------------------------------------------- 建 / 拆

  -- 自己这辆车的外模型（View 摆的那套）：坐在车里（乘员位）时不画（用户 11-22：「坦克内部屏幕会被挡住」——
  --   外模型的车体、炮塔块和内饰叠在一起，驾驶员眼前 4 厘米就是外模型车体的面，车长的显示屏前面是外模型的炮塔件）。
  --   看观瞄设备时（ownHide）也是它；车外、导演镜头、下车放回来
  --   从原车挖了内腔的（VehModels 的 M.carve，tools/models/carve.py；用户 11-23「在原车内部雕刻出来内饰」）：坐在乘员位上外壳照样画——
  --   车窗看出去是自己的车头、引擎盖、车门，跟车外看到的同一块玻璃；只藏原模型自带的简易内饰（inside），显示挖出来的内壁（cav）
  local function extHide(c, on, inOptic)
    local key = on and ((inOptic or not c or not c.carved) and "all" or "seat") or "off"
    if not c or c.extHidden == key then return end
    local v = G.viewById and G.viewById(c.id)
    if not v or not v.M then return end
    local cv = c.carved and v.M.carve
    -- 用原模型自带炮塔内饰的（spec.crewBox，InteriorAbrams）：坐在车里时外模型的炮、车体、车轮不画（从炮塔里看不见，炮尾那截还伸进乘员舱），
    --   炮塔的块中心在乘员舱的框里的也不画（M1A2 外模型炮塔里面那块实心的「炮塔底」、炮盾后面）；炮塔顶、舱盖、指挥塔照画——内饰顶上的开口从里面看是它们
    local box = c.spec and c.spec.crewBox
    local function cut(it)
      if not box then return false end
      local grp = it[2]
      if grp == "gun" or grp == "hull" or grp == "wheel" then return true end
      if grp ~= "turret" then return false end
      local q = it[3].Position - box.c
      return math.abs(q.X) < box.s.X / 2 and math.abs(q.Y) < box.s.Y / 2 and math.abs(q.Z) < box.s.Z / 2
    end
    for _, it in ipairs(v.M.parts) do
      local p = it[1]
      if p:IsA("BasePart") then p.LocalTransparencyModifier = ((key == "all") or (key == "seat" and cut(it))) and 1 or 0 end
    end
    if cv then
      for _, p in ipairs(cv.inside) do p.LocalTransparencyModifier = (key == "off") and 0 or 1 end
      for _, p in ipairs(cv.cav) do p.Transparency = (key == "seat") and 0 or 1 end
    end
    c.extHidden = key
  end

  local function teardown()
    if optic then exitOptic(nil) end
    if cur and not cur.spec.air then extHide(cur, false) end
    if cur and cur.spec.air then
      local v = G.viewById and G.viewById(cur.id)
      if cur.pilotsHidden and v and v.M then pcall(AM.setPilots, v.M, true) end
      for _, p in ipairs(cur.zone or {}) do p.LocalTransparencyModifier = 0 end
    end
    if cur then
      if cur.model then cur.model:Destroy() end
      cur = nil
    end
    table.clear(glintList)
    mode, station = nil, nil
    hint.Visible, title.Visible = false, false
    if hideUI then setHideUI(false) end
  end

  -- 乘员：按眼睛的位置反推骨盆（不同的小人身材不一样，头都正好在眼位）
  local function calib(f, c)
    local lean = c.lean or 0
    local rot = ANG(0, rad(c.yaw or 0), 0) * ANG(rad(lean * 0.6), 0, 0)
    local chest = ANG(rad(lean * 0.4), 0, 0)
    local J = f.J
    local k = f.head.Size.Y / 1.2
    local headInLT = J.Waist.c0 * chest * J.Waist.c1i * J.Neck.c0 * J.Neck.c1i
    local eyeInLT = (headInLT * CF(0, 0.1 * k, -0.42 * k)).Position
    c._rot, c._chest, c._eyeOff = rot, chest, eyeInLT
  end

  -- 第一人称只给白名单里的型号（Config.FirstPerson.only：用户 11-25 只留 M1A1、M1A2；nil = 全开）
  local function fpAllowed(id)
    local FP = G.Config.FirstPerson
    local only = FP and FP.only
    if not only then return true end
    return only[id] == true
  end
  G.interiorAllowed = fpAllowed

  local function build(st, v)
    if not fpAllowed(v.def.id) then return nil end
    local key = ALIAS[v.def.id] or v.def.id
    local fn = Defs[key]
    if not fn then return nil end
    local m = Instance.new("Model")
    m.Name = "Interior_" .. key
    local b = Kit.new(m)
    -- piv：炮塔座圈中心（车体坐标，格）——跟 frames 用的一样（导入的原模型按模型自己的座圈位置，不一定等于 VehDefs 写的）
    -- 挖了内腔的原车（重新导入过 carve.py 改过的 GLB）：内饰不画自己的车壳，按内腔摆（ctx.cav 查地板、顶、墙、窗户、乘员位）
    -- imp：导入的原模型（飞机的座舱屏幕位置、眼位在它的元数据里：F-16 坐进原模型自带的座舱）
    local piv0 = (v.M and v.M.tpiv) or (v.def.turret and v.def.turret.pivot) or Vector3.zero
    local cav = (v.M and v.M.carve and v.M.imported) and Cav.get(v.M.imported, piv0) or nil
    local ok, spec = pcall(fn, b, { def = v.def, piv = piv0, cav = cav,
      gpiv = (v.M and v.M.gpiv) or (v.def.gun and v.def.gun.pivot) or Vector3.zero, imp = v.M and v.M.imp })
    if not ok then
      m:Destroy()
      if G.showError then G.showError("local 内饰 " .. key .. "：" .. tostring(spec)) end
      return nil
    end
    -- 「开镜」= 炮长主瞄准镜（用户 11-22：「第一人称开镜视角移动不了」「坦克第一人称视角开镜有时候会是绿色的」）：一坐进车里是驾驶员位，
    --   原来 Shift 开的是驾驶员的热像 / 微光潜望镜——跟着车体、鼠标转不动，99A、国产装甲车的还是绿色微光。现在主镜跟着车体固定的位置（驾驶员），
    --   Shift 跟车外一样进炮长主瞄准镜（镜头在炮长镜里、鼠标 / 方向键转炮）；那个位置自己的镜子挪到 G、T
    -- 坦克不带机枪（VehDefs.TANK_MG，用户 11-22「坦克不要弄哪个机枪」）：遥控武器站的观瞄（M1A2 车长的 CROWS）从乘员位上拿掉，T 那一位空着
    if not spec.air and v.def.noRoofMg then
      for _, sp in pairs(spec.stations or {}) do
        for slot, o in pairs(sp.optics or {}) do
          if o.rws then sp.optics[slot] = nil end
        end
      end
    end
    if not spec.air and v.def.turret and v.def.sight then
      for _, sp in pairs(spec.stations or {}) do
        local o = sp.optics
        local p0 = o and o.primary
        if p0 and p0.kind ~= "gps" and (p0.dir == "hull" or p0.dir == "rear") and not o.third then
          o.primary, o.alt, o.third = { kind = "gps" }, p0, o.alt
        end
      end
    end
    -- 坦克一进车里默认是炮长位（内饰函数返回 lock = "gunner"，原来 11-23「就只锁定开炮手」锁死在炮长位；
    --   用户 11-24：「为什么给我默认炮长位控不了，我要能开别的位置」——不锁了：F2 驾驶员、F3 炮长、F4 车长、F5 装填手照常换）；
    --   车长的主观瞄（99A 周视镜 / M1A2 CITV）也挂在炮长位的 T（第三个）上，车外按 T 也是开它
    if spec.lock and spec.stations and spec.stations[spec.lock] then
      local sp = spec.stations[spec.lock]
      local cm = spec.stations.commander
      sp.optics = sp.optics or {}
      if cm and cm.optics and cm.optics.primary and cm.optics.primary.kind ~= "gps" and not sp.optics.third then
        sp.optics.third = cm.optics.primary
      end
      local o = { spec.lock }   -- 默认的乘员位排第一个，别的照原来的顺序
      for _, k in ipairs(spec.order or {}) do if k ~= spec.lock and spec.stations[k] then table.insert(o, k) end end
      spec.order = o
    end
    -- carved：坐在乘员位上外壳照样画——挖出来的内壁（v.M.carve.cav），或者用原模型自带车内的（spec.modelInt：M1A1 原模型的炮塔内饰，
    --   InteriorAbrams.lua；外模型里伸进乘员舱的块照 spec.crewBox 不画，见 extHide）
    local carvedOk = (cav ~= nil and spec.carved == true) or spec.modelInt == true
    local c = { key = key, id = st.id, b = b, spec = spec, model = m, crew = {}, data = {}, plist = {}, clist = {}, carved = carvedOk,
      env = { Map = G.Map }, recoilT = 99, loaded = true, loadT = nil, door = { L = 0, R = 0 }, lastRecoil = 0, hp0 = nil,
      dty = 0, dgp = 0, lastTy = v.ty or 0, lastGp = v.gp or 0, hitT = 99, citvA = 0, stub = {} }
    for i, it in ipairs(b.parts) do c.plist[i] = it[1] end
    -- 乘员：用户 11-22 晚「驾驶室不要显示人了」——车里、座舱里不建乘员小人（哪个视角都没有人，导演镜头也没有）；
    --   SHOW_CREW 打开就照原来画（乘员位视角时也藏着）
    for id, cs in pairs((SHOW_CREW and not spec.air) and spec.crew or {}) do
      local f = Kit.crew(cs.dress)
      if f then
        f.model.Parent = m
        calib(f, cs)
        c.crew[id] = { f = f, spec = cs }
      end
    end
    c.env.act = actions(c)
    c.env.zh = spec.air and spec.cn or nil   -- 中文座舱：屏幕写中文（坦克的中文屏幕自己有页面）
    -- 屏幕页面
    for _, s in ipairs(b.screens) do
      s.update = Screens.make(s, c.env)
      s.nextT = 0
    end
    -- 炮弹（装填手手上那一发）：子组 hround 挂在炮塔上，平时藏起来（没有乘员小人时不建：不然那发弹自己在空中飞）
    if spec.loader == "m256" and SHOW_CREW and not spec.air then
      b:group("hround", "turret", CF())
      local parts0 = #b.parts
      Defs.round120(b, "hround", CF(0, 0, 0.49), { len = 0.98 })
      c.hround = {}
      for i = parts0 + 1, #b.parts do
        c.plist[i] = b.parts[i][1]
        table.insert(c.hround, b.parts[i][1])
        b.parts[i][1].Transparency = 1
      end
    end
    if spec.loader == "carousel" then   -- 提弹机上的弹丸、药筒（平时藏着）
      b:group("lproj", "turret", CF())
      b:group("lchg", "turret", CF())
      local n0 = #b.parts
      b:cylZ("lproj", 0.58, 0.125, CF(), RGB(40, 40, 40), Enum.Material.Metal)
      b:cylZ("lproj", 0.08, 0.04, CF(0, 0, -0.32), RGB(30, 30, 30), Enum.Material.Metal)
      local n1 = #b.parts
      b:cylZ("lchg", 0.52, 0.125, CF(), RGB(170, 156, 112), Enum.Material.SmoothPlastic)
      b:cylZ("lchg", 0.03, 0.13, CF(0, 0, 0.27), RGB(150, 128, 82), Enum.Material.Metal)
      c.lproj, c.lchg = {}, {}
      for i = n0 + 1, #b.parts do
        c.plist[i] = b.parts[i][1]
        b.parts[i][1].Transparency = 1
        table.insert((i <= n1) and c.lproj or c.lchg, b.parts[i][1])
      end
    end
    -- 车内的扬尘、火星、烟（开炮、挨打）
    local fxp = Instance.new("Part")
    fxp.Size, fxp.Transparency, fxp.Anchored = V(0.2, 0.2, 0.2), 1, true
    fxp.CanCollide, fxp.CanQuery, fxp.CanTouch = false, false, false
    fxp.Parent = m
    c.fxp = fxp
    local function emitter(name, col, size, life, speed, light)
      local pe = Instance.new("ParticleEmitter")
      pe.Name = name
      pe.Rate = 0
      pe.Color = ColorSequence.new(col)
      pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 2.2) })
      pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
      pe.Lifetime = NumberRange.new(life * 0.6, life)
      pe.Speed = NumberRange.new(speed * 0.4, speed)
      pe.SpreadAngle = Vector2.new(180, 180)
      pe.LightEmission = light or 0
      pe.Drag = 2
      pe.Parent = fxp
      return pe
    end
    c.dust = emitter("Dust", RGB(170, 160, 140), 0.25, 2.5, 2)
    c.smoke = emitter("Smoke", RGB(60, 60, 58), 0.9, 5, 1.5)
    c.spark = emitter("Spark", RGB(255, 190, 90), 0.06, 0.5, 14, 1)
    c.spark.Acceleration = V(0, -40, 0)
    c.spark.Transparency = NumberSequence.new(0)
    return c
  end

  -- 弹架上显示的炮弹数（左门 18 发先用，跟着剩下的弹数）
  local function syncRack(c, n)
    local racks = c.b.named.racks
    if not racks then return end
    local i = 0
    for _, side in ipairs({ "R", "L" }) do
      for j = #racks[side], 1, -1 do
        i += 1
        local show = i <= n
        for _, p in ipairs(racks[side][j]) do if p then p.Transparency = show and 0 or 1 end end
      end
    end
    c.rackN = n
  end
  -- 转盘上的弹盒：剩几发露几个（自动装弹机里最多 22 发）
  local function syncCarousel(c, n)
    local cas = c.b.named.cassettes
    if not cas then return end
    for i, cs in ipairs(cas) do
      local show = i <= n
      cs.used = not show
      for j = 2, 4 do if cs.parts[j] then cs.parts[j].Transparency = show and 0 or 1 end end
    end
    c.rackN = n
  end
  -- 装填手要去拿的那一发（左门弹架上最前面还在的）
  local function nextRackRound(c)
    local racks = c.b.named.racks
    if not racks then return nil end
    for _, side in ipairs({ "L", "R" }) do
      for _, rd in ipairs(racks[side]) do
        if rd[1].Transparency < 0.5 then return rd, side end
      end
    end
    return nil
  end

  ---------------------------------------------------------------- 各组的世界姿态

  local function frames(c, v)
    local b = c.b
    if c.spec.air then   -- 飞机：座舱的原点在飞行员眼位（机体坐标里，跟着机身俯仰滚转）
      local w = v.cf * CF(c.eyeBody)
      b.groups.hull.world, b.groups.turret.world, b.groups.gun.world = w, w, w
      for _, g in ipairs(b.gorder) do
        if g.parent then g.world = g.parent.world * g.pivot * g.anim end
      end
      return
    end
    local M, d = v.M, v.def
    local piv = (M and M.tpiv) or d.turret.pivot
    local gpiv = (M and M.gpiv) or d.gun.pivot
    local hullF = v.hullF or v.cf
    local tF = v.tF or (hullF * CF(piv))
    b.groups.hull.world = hullF * CF(piv)
    b.groups.turret.world = tF
    b.groups.gun.world = tF * CF(gpiv) * ANG(rad(v.gp or 0), 0, 0)
    for _, g in ipairs(b.gorder) do
      if g.parent then g.world = g.parent.world * g.pivot * g.anim end
    end
  end
  local function pose(c)
    local plist, clist = c.plist, c.clist
    local parts = c.b.parts
    for i = 1, #parts do
      local it = parts[i]
      clist[i] = it[2].world * it[3]
    end
    workspace:BulkMoveTo(plist, clist, Enum.BulkMoveMode.FireCFrameChanged)
  end
  local function at(c, g, p)   -- 某组上一点（米）的世界位置
    local grp = c.b.groups[g] or c.b.groups.turret
    return grp.world * (p * S)
  end

  ---------------------------------------------------------------- 动画

  -- 装填手的一套动作（M256：手工装填），按装填时间 dur 缩放；返回 { pelvis 偏航角, 眼位, 左右手, 炮弹姿态（炮塔里，或者炮膛里）, 门, 膝动开关, 炮闩 }
  local LOAD = {   -- t 是 0～1 的进度
    { t = 0.00, yaw = -28, eye = V(-0.60, 0.56, 0.10), door = 0, blk = 1 },
    { t = 0.10, yaw = 120, eye = V(-0.62, 0.50, 0.42), door = 0, blk = 1, knee = 1 },
    { t = 0.18, yaw = 165, eye = V(-0.58, 0.46, 0.52), door = 1, blk = 1, knee = 1, grab = 0 },
    { t = 0.30, yaw = 170, eye = V(-0.58, 0.48, 0.40), door = 1, blk = 1, knee = 1, grab = 0.75 },
    { t = 0.40, yaw = 150, eye = V(-0.62, 0.52, 0.30), door = 0, blk = 1, grab = 1.0 },
    { t = 0.55, yaw = 10, eye = V(-0.55, 0.56, 0.05), door = 0, blk = 1, flip = 1 },
    { t = 0.66, yaw = -30, eye = V(-0.42, 0.54, -0.05), door = 0, blk = 1, ram = 0 },
    { t = 0.76, yaw = -32, eye = V(-0.40, 0.52, -0.10), door = 0, blk = 1, ram = 1 },
    { t = 0.80, yaw = -32, eye = V(-0.42, 0.53, -0.05), door = 0, blk = 0, ram = 1 },
    { t = 0.90, yaw = -40, eye = V(-0.66, 0.56, 0.10), door = 0, blk = 0, arm = 1 },
    { t = 1.00, yaw = -28, eye = V(-0.60, 0.56, 0.10), door = 0, blk = 0 },
  }
  local function keyAt(k)
    for i = 2, #LOAD do
      if k <= LOAD[i].t then
        local a, b = LOAD[i - 1], LOAD[i]
        return a, b, sm((k - a.t) / (b.t - a.t))
      end
    end
    return LOAD[#LOAD], LOAD[#LOAD], 0
  end

  -- 把子组摆到某个世界姿态（反推 anim）
  local function setWorld(c, gname, w)
    local g = c.b.groups[gname]
    if not g or not g.parent then return end
    g.anim = (g.parent.world * g.pivot):Inverse() * w
    g.world = w
  end
  local function showParts(list, on) for _, p in ipairs(list or {}) do p.Transparency = on and 0 or 1 end end
  -- 转盘式自动装弹机（99A / 96）：转盘转到要的弹种 → 提弹 → 推弹丸 → 抬一格 → 推药筒 → 关闩 → 提弹架落回去
  local function animCarousel(c, k, dt)
    local b = c.b
    local cas = b.named.cassettes
    if not cas then return 0 end
    local gW = b.groups.gun.world
    local rest = b.groups.turret.world * b.groups.lift.pivot
    if not c.slot then   -- 选下一个弹盒（同弹种里还在的第一个）
      for i, cs in ipairs(cas) do
        if not cs.used and cs.kind == (c.ammoKind or "ap") then c.slot = i break end
      end
      c.slot = c.slot or 1
      c.carA0 = c.carA or 0
      local want = math.pi - cas[c.slot].a
      local d = (want - c.carA0 + math.pi) % (2 * math.pi) - math.pi
      c.carA1 = c.carA0 + d
    end
    local u = sm(k / 0.22)
    c.carA = c.carA0 + (c.carA1 - c.carA0) * u
    b:setAnim("carousel", ANG(0, c.carA, 0))
    local cs = cas[c.slot]
    if k > 0.22 and not cs.used then
      cs.used = true
      showParts({ cs.parts[2], cs.parts[3], cs.parts[4] }, false)
      showParts(c.lproj, true)
      showParts(c.lchg, true)
    end
    local up = gW * CF(V(0, -0.07, 1.21) * S)   -- 弹丸那一层对准炮膛
    local tray
    if k < 0.22 then tray = rest
    elseif k < 0.42 then tray = rest:Lerp(up, sm((k - 0.22) / 0.20))
    elseif k < 0.58 then tray = up
    elseif k < 0.64 then tray = up * CF(V(0, -0.13 * sm((k - 0.58) / 0.06), 0) * S)
    elseif k < 0.84 then tray = up * CF(V(0, -0.13, 0) * S)
    else tray = (up * CF(V(0, -0.13, 0) * S)):Lerp(rest, sm((k - 0.84) / 0.16)) end
    setWorld(c, "lift", tray)
    -- 弹丸、药筒
    if k > 0.22 then
      if k < 0.42 then
        setWorld(c, "lproj", tray * CF(V(0, 0.07, -0.02) * S))
      elseif k < 0.58 then
        local z = 1.19 - 1.13 * sm((k - 0.42) / 0.16)
        setWorld(c, "lproj", gW * CF(V(0, 0, z) * S))
        if k > 0.56 then showParts(c.lproj, false) end
      end
      if k < 0.64 then
        setWorld(c, "lchg", tray * CF(V(0, 0.20, 0.01) * S))
      elseif k < 0.78 then
        local z = 1.22 - 0.61 * sm((k - 0.64) / 0.14)
        setWorld(c, "lchg", gW * CF(V(0, 0, z) * S))
        if k > 0.76 then showParts(c.lchg, false) end
      end
    end
    -- 链式推弹机：两次往前推
    local ram = 0
    if k > 0.42 and k < 0.58 then ram = math.sin((k - 0.42) / 0.16 * math.pi)
    elseif k > 0.64 and k < 0.78 then ram = math.sin((k - 0.64) / 0.14 * math.pi) end
    b:setAnim("rammer", CF(0, 0, -0.50 * ram))
    return (k < 0.80) and 1 or math.max(0, 1 - (k - 0.80) / 0.04)
  end

  local function stepAnim(c, v, st, dt)
    local b, spec = c.b, c.spec
    local now = os.clock()
    -- 开炮：View 的后坐量一下子涨上去
    local rc = v.recoil or 0
    local shots = v.shots or 0   -- 这辆车开了第几炮（View 的 G.vehRecoil 数的；后坐曲线现在有个起势，不能再按后坐量一下子涨多少认开炮）
    if c.lastShots == nil then c.lastShots = shots end   -- 刚坐进来：之前开过的不算
    if shots ~= c.lastShots then
      c.recoilT = 0
      c.loaded = false
      c.fired = true
      shake = math.max(shake, 1)
      for _, L in ipairs(b.lights) do if L.role == "flash" then L.pulse = 1 end end
      c.fxp.CFrame = CF(at(c, "turret", V(0, 0.3, 0)))
      c.dust:Emit(28)
    end
    c.lastRecoil = rc
    c.lastShots = shots
    c.recoilT += dt
    local K = spec.gunK or 0.3
    local rt = c.recoilT
    -- 炮尾的后坐：跟车外的炮管同一条曲线（View 的 G.recoilCurve：0.08 秒坐到底、顶住一下、0.62 秒复进完；原来 0.05 秒直线坐到底，看着像一下子跳过去）
    local big = v.recoilBig
    if big == nil then big = (v.def and (v.def.cat == "tank" or v.def.cat == "arty")) or false end
    local r = K * (G.recoilCurve and G.recoilCurve(rt, big) or ((rt < 0.6) and (1 - sm(math.max(0, rt - 0.05) / 0.55)) or 0))
    b:setAnim("recoil", CF(0, 0, r))
    -- 炮闩：复进的时候自动打开（落下），装上弹关上
    local w = VD.W[st and st.d and st.d.weapons and st.d.weapons[st.wi or 1] or ""] or VD.W.gun120
    local dur = math.max(3.5, (w and w.rate) or 6)
    if c.fired and rt > 0.45 and not c.loadT then
      c.loadT = 0
      if c.smoke and rt < 0.6 then
        c.fxp.CFrame = CF(at(c, "gun", V(0, 0.1, 0.9)))
        c.smoke:Emit(6)
      end
    end
    local blkOpen = (c.fired and rt > 0.4) and 1 or 0
    local doorL, knee, armK = 0, 0, 0
    local lo = nil
    if c.loadT then
      c.loadT += dt
      local k = c.loadT / (dur - 0.5)
      if k >= 1 then
        c.loadT, c.fired, c.loaded = nil, false, true
        c.carry, c.slot = nil, nil
        for _, p in ipairs(c.hround or {}) do p.Transparency = 1 end
        if spec.loader == "carousel" then
          c.carN = math.max(0, (c.carN or c.rackN or 22) - 1)
          showParts(c.lproj, false)
          showParts(c.lchg, false)
          setWorld(c, "lift", c.b.groups.turret.world * c.b.groups.lift.pivot)
          b:setAnim("rammer", CF())
        end
      elseif spec.loader == "carousel" then
        blkOpen = animCarousel(c, k, dt)
      else
        local a, bb, u = keyAt(k)
        lo = { a = a, b = bb, u = u, k = k }
        doorL = (a.door or 0) + ((bb.door or 0) - (a.door or 0)) * u
        knee = math.max(a.knee or 0, bb.knee or 0) * ((a.knee and bb.knee) and 1 or u)
        blkOpen = (a.blk or 0) + ((bb.blk or 0) - (a.blk or 0)) * u
        armK = ((a.arm or 0) + ((bb.arm or 0) - (a.arm or 0)) * u)
        -- 拿炮弹那一下：弹架上的那发藏起来，手上的露出来
        if k > 0.24 and not c.carry then
          local rd = nextRackRound(c)
          c.carry = rd or true
          if type(rd) == "table" then
            c.carryFrom = rd[1].CFrame
            for _, p in ipairs(rd) do if p then p.Transparency = 1 end end
          end
          for _, p in ipairs(c.hround or {}) do p.Transparency = 0 end
        end
      end
    end
    if b.groups.stubport then   -- 药筒底盘从炮塔顶后部的抛壳窗抛出去：窗开一下
      local o = (rt > 0.15 and rt < 0.9) and math.sin(math.min(1, (rt - 0.15) / 0.75) * math.pi) or 0
      b:setAnim("stubport", ANG(rad(-75 * o), 0, 0))
    end
    b:setAnim("blk", CF(0, -0.13 * blkOpen, 0))
    b:setAnim("brk", ANG(0, 0, rad(-50 * blkOpen)))
    c.door.L += (doorL - c.door.L) * math.min(1, dt * 10)
    b:setAnim("doorL", CF(-0.84 * c.door.L, 0, 0))
    b:setAnim("knee", ANG(rad(-25 * knee), 0, 0))
    b:setAnim("arm", ANG(rad(armK > 0.5 and 0 or -40), 0, 0))
    c.lo = lo
    -- 炮长双握把：跟着炮塔转、炮俯仰的速度摆
    local ty, gp = v.ty or 0, v.gp or 0
    local dty = ((ty - c.lastTy + 180) % 360 - 180) / math.max(dt, 1e-3)
    local dgp = (gp - c.lastGp) / math.max(dt, 1e-3)
    c.lastTy, c.lastGp = ty, gp
    c.dty += (dty - c.dty) * math.min(1, dt * 8)
    c.dgp += (dgp - c.dgp) * math.min(1, dt * 8)
    b:setAnim("gch", ANG(rad(clamp(-c.dgp * 0.8, -14, 14)), 0, rad(clamp(-c.dty * 0.35, -16, 16))))
    -- 驾驶员 T 形把 / 方向盘：跟着方向
    b:setAnim("tbar", ANG(0, rad(-clamp(v.steer or 0, -1, 1) * 26), 0))
    b:setAnim("swheel", ANG(0, 0, rad(-clamp(v.steer or 0, -1, 1) * 120)))
    -- 装填手潜望镜慢慢转着看
    b:setAnim("lscope", ANG(0, math.sin(now * 0.21) * 0.6, 0))
    -- 灯、指示灯
    for _, L in ipairs(b.lights) do
      if L.role == "dome" then
        local col = LIGHTS[lightMode]
        local kk = LIGHTK[lightMode]
        if c.hitT < 1.6 then kk = kk * ((math.random() < 0.45) and 0.05 or 1) end
        L.L.Color = col
        L.L.Brightness = L.bright * kk
        L.L.Enabled = kk > 0
      elseif L.role == "flash" then
        L.pulse = math.max(0, (L.pulse or 0) - dt * 7)
        L.L.Brightness = (L.pulse or 0) * 8
        L.L.Enabled = (L.pulse or 0) > 0.01
      elseif L.role == "warn" then
        local on = c.hitT < 6 and (math.floor(now * 4) % 2 == 0)
        L.L.Enabled = on
        L.L.Brightness = on and 1.4 or 0
      end
    end
    for _, l in ipairs(b.leds) do
      local on = true
      if l.role == "ready" then on = c.loaded
      elseif l.role == "radio" then on = math.noise(now * 3, l.p.Position.X) > -0.1
      elseif l.role == "key" then on = (l.s and l.s.ledOn and l.s.ledOn(l.k)) and true or false   -- 键上的灯：屏幕页面说了算（选中的那个键亮）
      elseif l.role == "domeLamp" then
        l.p.Color = (lightMode == 4) and RGB(40, 40, 40) or LIGHTS[lightMode]
        on = nil
      end
      if c.lampT and os.clock() < c.lampT then on = true end   -- 灯检：全亮
      if on ~= nil then l.p.Color = on and l.on or l.off end
    end
    -- 挨打：血一下子少了
    local em = st and st.em
    local hp = em and em:GetAttribute("Hp")
    if hp and c.hp0 and hp < c.hp0 - 1 then
      c.hitT = 0
      shake = math.max(shake, 2.2)
      c.fxp.CFrame = CF(at(c, "turret", V((math.random() - 0.5) * 1.6, 0.3 + math.random() * 0.4, (math.random() - 0.5) * 1.4)))
      c.spark:Emit(40)
      c.smoke:Emit(18)
    end
    c.hp0 = hp
    c.hitT += dt
  end

  -- 乘员摆姿势
  local function stepCrew(c, camLook)
    for id, cr in pairs(c.crew) do
      local f, cs = cr.f, cr.spec
      local g = c.b.groups[cs.g] or c.b.groups.turret
      local rot, chest, eyeOff = cs._rot, cs._chest, cs._eyeOff
      local eye = cs.eye
      local lookW = g.world:VectorToWorldSpace(cs.look or V(0, 0, -1))
      local lh, rh, lf, rf
      local function tgt(h)
        if not h then return nil end
        return at(c, h[1], h[2])
      end
      lh, rh = tgt(cs.hands and cs.hands.l), tgt(cs.hands and cs.hands.r)
      lf, rf = tgt(cs.feet and cs.feet.l), tgt(cs.feet and cs.feet.r)
      if id == "loader" and c.lo then   -- 装填的动作
        local L = c.lo
        local yaw = L.a.yaw + (L.b.yaw - L.a.yaw) * L.u
        -- 关键帧是照 M1A2 那套内饰排的：按这辆车装填手自己的眼位平移（B 的 M1A1 原模型内饰装填手站得不一样）
        eye = cs.eye + (L.a.eye:Lerp(L.b.eye, L.u) - LOAD[1].eye)
        rot = ANG(0, rad(yaw), 0) * ANG(rad((cs.lean or 0) * 0.6 - 8), 0, 0)
        chest = ANG(rad(-14), 0, 0)
        local hr = c.b.groups.hround
        if c.carry and hr then
          lh = hr.world * (V(0, -0.06, -0.20) * S)
          rh = hr.world * (V(0.02, -0.02, 0.47) * S)
          lookW = (hr.world.Position - (g.world * (eye * S))).Unit
        elseif L.k < 0.2 then
          local door = c.b.groups.doorL and at(c, "doorL", V(0, 0, 0)) or (g.world * ((cs.eye + V(0.15, -0.35, 0.95)) * S))   -- 没有弹药门：身后偏右
          lh = c.b.groups.doorL and at(c, "doorL", V(0.30 + 0.0, 0, -0.05)) or door
          rh = nil
          lookW = (door - g.world * (eye * S)).Unit
        elseif L.k > 0.8 then
          lh = nil
          rh = c.b.groups.arm and at(c, "arm", V(0, 0.10, 0)) or at(c, "gun", V(-0.35, 0.12, 0.85))   -- 没有保险拨杆的组：炮尾左边
          lookW = (at(c, "gun", V(0, 0.1, 0.8)) - g.world * (eye * S)).Unit
        end
        if (L.a.knee or L.b.knee) then
          rf = c.b.groups.knee and at(c, "knee", V(0.0, 0.10, -0.08)) or (g.world * ((cs.eye + V(0.22, -1.25, 0.30)) * S))
        end
      end
      local eyeCF = g.world * CF(eye * S) * rot
      local pelvis = eyeCF * CF(-eyeOff)
      if c.mine == id and camLook then lookW = camLook end
      f.set({ pelvis = pelvis, chest = chest, look = lookW, lh = lh, rh = rh, lf = lf, rf = rf, footRot = g.world.Rotation * ANG(rad(cs.footPitch or 0), 0, 0) })
      -- 第一人称坐在车里（乘员位）：自己那个位置的小人不画（用户 11-21「不要显示我的腿和胳膊」）；别的乘员 11-22 关过（「不要显示成员和自己的身体部位」），
      --   11-24 又要（「坦克要有精细的 roblox 人物有不同的动画来负责干不同的活」）；导演镜头从外面看照画
      local show = mode ~= "seat" or id ~= c.mine   -- 11-24：别的乘员照画（各干各的活），自己那个位置的不画（看得见自己的胳膊腿：11-21 不要）
      if cr.headShown ~= show then
        cr.headShown = show
        f.bodyVisible(show)
      end
    end
  end

  -- 装填手手上的炮弹：拿出来 → 翻过来 → 对准炮膛 → 推进去
  local function stepRound(c)
    local hr = c.b.groups.hround
    if not hr or not c.lo or not c.carry then return end
    local L = c.lo
    local tW = c.b.groups.turret.world
    local k = L.k
    local cfT
    if k < 0.40 then   -- 从弹架里抽出来（弹尖朝后）
      local u = sm((k - 0.24) / 0.16)
      -- 手上那发和弹架上那发对齐：弹架那发的弹底零件往弹尖挪 0.47 米就是炮弹中间（手上那发的原点）
      local from = c.carryFrom and tW:ToObjectSpace(c.carryFrom * CF(0, 0, -0.47 * S)) or (CF(V(-0.55, 0.45, 1.6) * S) * ANG(0, math.pi, 0))
      cfT = from:Lerp(CF(V(-0.62, 0.30, 0.55) * S) * ANG(0, math.pi, 0), u)
    elseif k < 0.66 then   -- 转身、把炮弹翻过来（弹尖朝前），端到炮尾后面
      local u = sm((k - 0.40) / 0.26)
      local a = CF(V(-0.62, 0.30, 0.55) * S) * ANG(0, math.pi, 0)
      local gW = c.b.groups.gun.world
      local bW = gW * CF(V(0, -0.02, 1.44) * S)   -- 炮尾后面：弹尖正对药室口
      local bT = tW:ToObjectSpace(bW)
      cfT = a:Lerp(bT, u)
    else   -- 推进炮膛
      local u = sm((k - 0.66) / 0.10)
      local gW = c.b.groups.gun.world
      local zz = 1.44 - 0.98 * u   -- 推到弹底和炮尾端面齐平
      cfT = tW:ToObjectSpace(gW * CF(V(0, -0.02, zz) * S))
      if k > 0.78 then
        for _, p in ipairs(c.hround) do p.Transparency = 1 end
      end
    end
    -- 子组 hround 的世界姿态 = 炮塔 × anim（支点是原点）；炮弹模型的原点在弹底前 0.49 米（中间）
    hr.anim = cfT
    hr.world = tW * cfT
  end

  ---------------------------------------------------------------- 屏幕的数据

  local entsT, entsList = 0, {}
  -- 地图上的军标按兵种分（InteriorScreens 的 Sym）：车按 Cat（坦克、防空、炮兵，别的算装甲车），飞机按型号分直升机 / 固定翼，工事按种类
  local ADm = nil
  local FORT_TYP = { aaa = "aa", howitzer = "arty", coastal = "arty", bunker = "fort" }
  local function entTyp(kind, cat, mid)
    if kind == "veh" then   -- 实体的 Cat 是挨打的类别（armor / light……），兵种按型号表（VehDefs 的 cat）
      local vd = mid and VD.get(mid)
      local c2 = vd and vd.cat or cat
      return (c2 == "tank" or c2 == "aa" or c2 == "arty") and c2 or "apc"
    end
    if kind == "air" then
      if ADm == nil then
        local ok, m = pcall(function() return require(RS:WaitForChild("AirDefs")) end)
        ADm = ok and m or false
      end
      local ad = ADm and ADm.get and mid and ADm.get(mid)
      return (ad and ad.kind == "heli") and "heli" or "jet"
    end
    if kind == "ship" then return "ship" end
    if kind == "fort" then return FORT_TYP[mid or ""] or "fort" end
    return "inf"
  end
  local function nearbyEnts(pos, myId)
    local now = os.clock()
    if now - entsT < 0.25 then return entsList end
    entsT = now
    entsList = {}
    local folder = workspace:FindFirstChild("Ents")
    if folder then
      for _, em in ipairs(folder:GetChildren()) do
        local root = em:FindFirstChild("Root")
        local id = em:GetAttribute("EntId")
        if root and id ~= myId and (em:GetAttribute("Hp") or 1) > 0 then
          local p = root.Position
          local dd = (p - pos).Magnitude
          if dd < 4500 then
            local kind = em:GetAttribute("Kind")
            local sz = root.Size
            table.insert(entsList, { pos = p, team = em:GetAttribute("Team"), kind = (kind == "veh" or kind == "ship" or kind == "fort") and "veh" or ((kind == "air") and "air" or "inf"),
              typ = entTyp(kind, em:GetAttribute("Cat"), em:GetAttribute("Model")), w = math.max(sz.X, sz.Z), h = sz.Y, seen = dd < 1100 })
          end
        end
      end
    end
    for _, pl in ipairs(Players:GetPlayers()) do
      local ch = pl.Character
      local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
      if hrp and pl ~= me and (hrp.Position - pos).Magnitude < 3000 then
        local hum = ch:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 and (ch:FindFirstChild("Head") and ch.Head.Transparency < 0.9) then
          table.insert(entsList, { pos = hrp.Position, team = pl:GetAttribute("Side"), kind = "inf", typ = "inf", w = 2, h = 5, seen = (hrp.Position - pos).Magnitude < 900 })
        end
      end
    end
    return entsList
  end

  local function basis(cf)
    return cf.Position, cf.LookVector, cf.RightVector, cf.UpVector
  end
  local function gather(c, v, st)
    local d = c.data
    local b = c.b
    d.t = os.clock()
    d.clock = (Lighting.ClockTime or 0) * 3600
    d.speed = st.speed or v.speed or 0
    d.rpm = clamp(math.abs(d.speed) / math.max(st.d.speed or 30, 1) * 0.85 + 0.15, 0.15, 1)
    d.gear = (d.speed > 0.6 and "D") or (d.speed < -0.6 and "R") or "N"
    local em = st.em
    local hp, mh = em and em:GetAttribute("Hp"), em and em:GetAttribute("MaxHp")
    d.hp = (hp and mh and mh > 0) and hp / mh or 1
    d.fuel = em and em:GetAttribute("Fuel") or 0.84
    d.ty, d.gp = v.ty or 0, v.gp or 0
    local hullW = b.groups.hull.world
    local lk = hullW.LookVector
    d.hdg = math.deg(math.atan2(lk.X, -lk.Z)) % 360
    d.pos = hullW.Position
    d.team = G.S and G.S.team
    d.ents = nearbyEnts(d.pos, st.id)
    d.points = {}
    if G.S and G.S.points then
      for _, p in ipairs(G.S.points) do
        for _, mp in ipairs(G.Map.POINTS) do
          if mp.id == p.id then table.insert(d.points, { id = p.id, x = mp.x, z = mp.z, owner = p.owner }) end
        end
      end
    end
    local wid = st.d.weapons and st.d.weapons[st.wi or 1]
    d.wid = wid
    local ammo = G.S and G.S.veh and G.S.veh.ammo and wid and G.S.veh.ammo[wid]
    d.ready = c.loaded and (not ammo or (ammo[1] or 0) > 0)
    d.range = st.aimPt and ((st.aimPt - at(c, "gun", V(0, 0, 0))).Magnitude / S) or nil
    d.fwd = lk   -- 防空雷达（车头朝上）
    d.turretDeg, d.gunDeg = d.ty, d.gp   -- 火控计算机：方位、射角
    d.ammo = ammo and ((ammo[1] or 0) + (ammo[2] or 0)) or 0
    d.ammoName = wid and string.upper(tostring(wid)) or "--"
    d.pol = (st.mode == 4 or (st.mode ~= 3 and st.pol == "BLK")) and "BLK" or "WHT"
    -- 视场：Drive 的倍率档（SEPv2 热像 3 / 6 / 13 / 25 / 50 倍……）
    local Z, zi = nil, st.zoom or 1
    if G.driveZooms then Z, zi = G.driveZooms() end
    d.zoomFov = (Z and Z[zi or 1]) or ((st.zoom == 2) and 7 or 20)
    d.zoomTxt = string.format("%dX", math.floor(70 / d.zoomFov + 0.5))
    if d.zoomTxt == "4X" then d.zoomTxt = "3X" end   -- 默认两档（20°、7°）照旧叫 3X / 10X
    -- 热像的视线：驾驶员（车头）、主瞄准镜（炮）、独立热像仪（车长看的方向）、遥控武器站
    local hE = hullW * CF(V(0, 0.10, -2.4) * S)
    d.hullEye, d.hullF, d.hullR, d.hullU = basis(hE)
    local gW = b.groups.gun.world
    d.gunEye = (b.groups.turret.world * CF(V(0.62, 0.95, -1.0) * S)).Position   -- 主瞄准镜的镜头（炮塔顶右前）
    d.gunF, d.gunR, d.gunU = gW.LookVector, gW.RightVector, gW.UpVector
    local tW = b.groups.turret.world
    -- 热像仪方向：手动扫描（车长位上跟着车长看的方向；不在车长位就停在上次的方向）、自动扫描（炮塔正面 ±60° 来回扫）、随炮
    local cm = c.citvMode or "MAN"
    local citvDir
    if cm == "GUN LOS" or cm == "GPS LOS" then
      citvDir = gW.LookVector
    elseif cm == "AUTO" then   -- 扇区：默认炮塔正面 ±60°，SCAN L / SCAN R 键把左右边设在按键时热像仪指的方向；角速度一样（大约每秒 21°）
      local sec = c.citvSec or { -60, 60 }
      local mid, half = (sec[1] + sec[2]) / 2, math.max(5, math.abs(sec[2] - sec[1]) / 2)
      c.citvA = -math.rad(mid + math.sin(os.clock() * 0.35 * 60 / half) * half)
      citvDir = (tW * ANG(0, c.citvA, 0)).LookVector
    elseif cm == "STOW" then   -- 收回：朝炮塔正前
      citvDir = tW.LookVector
    elseif mode == "seat" and station == "commander" and not scopePhase() then
      citvDir = cam.CFrame.LookVector
      c.citvMan = tW:VectorToObjectSpace(citvDir)
    else
      citvDir = c.citvMan and tW:VectorToWorldSpace(c.citvMan) or tW.LookVector
    end
    local cE = tW * CF(V(-0.45, 1.05, -0.75) * S)
    local cCF = CFrame.lookAt(cE.Position, cE.Position + citvDir)
    d.citvEye, d.citvF, d.citvR, d.citvU = basis(cCF)
    local rel = math.deg(math.atan2(tW.RightVector:Dot(citvDir), tW.LookVector:Dot(citvDir)))
    d.citvRel = rel
    d.citvFov = c.citvFov or 22
    d.citvMode = cm
    d.engineOff = G.interiorEngineOff == true
    local fc = st.fcs   -- 火控（Drive.lua）：弹种、激光测的距离、测距的时刻——CITV 屏下面的弹种字母和距离
    d.fcsAm, d.fcsR, d.fcsLaseT = fc and fc.am, fc and fc.R, fc and fc.laseT
    d.fcsMan, d.fcsNoRet = fc and fc.man, fc and fc.noRet   -- 手动装定的距离、没回波
    d.fcsAim, d.fcsSE = st.fcsAim, st.fcsSE   -- 弹道计算机正在用的距离、飞行时间、超高角（弧度）
    d.sightMode, d.zoom = st.mode, st.zoom
    -- 炮长面板上的开关（Drive 的火控状态）：激光首 / 末回波、多回波、保险，火控方式，稳定器，炮管热弯曲没修正的量，校炮偏差，战斗瞄准距离，
    --   分划 / 符号亮度、分划照明、热像增益 / 电平；自检、炮口基准更新、车长热像仪测距的时刻
    d.lrf, d.multi, d.arm = fc and fc.lrf or "LAST", fc and fc.multi or false, not (fc and fc.arm == false)
    d.fcsMode = fc and fc.mode or 1
    d.stab = st.stab ~= false
    d.droopErr = fc and ((fc.droop or 0) - (fc.mrs or 0)) or 0
    d.droop = fc and fc.droop or 0
    d.bore = fc and fc.bore or { 0, 0 }
    d.bsR = fc and fc.am and fc.bsR and fc.bsR[fc.am] or nil
    d.retLvl, d.symLvl, d.retNight, d.thGain, d.thLevel = st.retLvl or 0, st.symLvl or 0, st.retNight == true, st.thGain or 2, st.thLevel or 2
    d.rof, d.wpn, d.armSafe = st.rof or "HI", st.wi or 1, st.safe == true   -- 布雷德利：射速、武器、保险（IBAS 显示器下沿）
    d.bitT, d.mrsT = c.bitT, c.mrsT
    d.citvRange, d.citvRT = c.citvR, c.citvRT
    d.cant = -math.deg(math.asin(clamp(hullW.RightVector.Y, -1, 1)))   -- 车体侧倾（耳轴倾斜）：右边低是正
    d.ammoAll = G.S and G.S.veh and G.S.veh.ammo or {}
    d.ammoKind = c.ammoKind
    if v.rF then d.rwsEye, d.rwsF, d.rwsR, d.rwsU = basis(v.rgF or v.rF) else d.rwsEye, d.rwsF, d.rwsR, d.rwsU = basis(tW * CF(V(0.6, 1.3, 0.2) * S)) end
    d.rwsAmmo = 400
    -- 坦克不带机枪（VehDefs.TANK_MG）：CROWS 屏只剩车顶摄像头，没有 M2、没有弹数
    if st and st.d and st.d.noRoofMg then d.rwsAmmo, d.rwsNoGun = nil, true end
    return d
  end

  local function stepScreens(c, v, st)
    local now = os.clock()
    local camP = cam.CFrame.Position
    local camL = cam.CFrame.LookVector
    local d = nil
    for _, s in ipairs(c.b.screens) do
      if s.update and now >= s.nextT then
        local q = s.part.Position - camP
        local near = q.Magnitude < 2.6 * S and q.Unit:Dot(camL) > 0.3
        s.nextT = now + (near and 0.1 or 0.5) + math.random() * 0.03
        d = d or gather(c, v, st)
        local ok, err = pcall(s.update, d)
        if not ok then
          s.update = nil
          warn("[内饰] 屏幕 " .. tostring(s.page) .. "：" .. tostring(err))
        end
      end
    end
  end

  ---------------------------------------------------------------- 屏幕边的按键：对准、左键按

  -- 按键按下去以后真起作用的事
  actions = function(c)
    local A = {}
    function A.designate()   -- 猎-歼：炮塔转到热像仪看的方向（炮长接着打）
      local st = G.drive
      local d = c.data
      if st and d.citvEye and d.citvF then st.aimPt = d.citvEye + d.citvF * 3000 end
    end
    function A.polarity()
      local st = G.drive
      if not st then return end
      st.mode = (st.mode == 4) and 3 or 4
      st.pol = (st.mode == 4) and "BLK" or "WHT"
      if G.driveApplySight then G.driveApplySight() end
    end
    function A.zoom()   -- 视场下一档（SEPv2 热像 3 / 6 / 13 / 25 / 50 倍，昼光 3 / 10 倍；别的车两档）
      local st = G.drive
      if not st then return end
      if G.driveZoomStep then G.driveZoomStep() else st.zoom = (st.zoom == 2) and 1 or 2 end
    end
    -- 昼光 / 热像（M1A1 主瞄准镜的视野选择：白天的光学通道、热像仪通道）：从昼光、微光换到热像（白热），热像换回昼光；下次开镜生效
    function A.thermal()
      local st = G.drive
      if not st then return end
      st.mode = ((st.mode or 1) >= 3) and 1 or 3
      if G.sightPref then G.sightPref[(G.isNight and G.isNight()) and "night" or "day"] = st.mode end
    end
    function A.lase() if G.driveLase then G.driveLase() end end   -- 激光测距（同 R 键：瞄准线打到哪、多远）
    function A.range(m) if G.driveRange then G.driveRange(m) end end   -- 手动装定距离（米；nil 回到战斗瞄准距离）：弹道计算机就按它算超高角
    function A.fcsMode(k)   -- 火控方式 1 正常 / 2 应急 / 3 手动（Drive.lua：应急没有提前量，手动没有弹道计算机、没有稳定、手摇）
      c.fcsMode = k
      if G.driveSetFcs then G.driveSetFcs(k) end
    end
    ---------------- 炮长面板上的旋钮、开关、按钮（InteriorAbrams 的 KNOBS：B:mov 的 on）——都接到 Drive.lua 的火控上
    local AMMO4 = { "SABOT", "HEAT", "MPAT", "CAN" }
    local function set(f, v) if G.driveSet then G.driveSet(f, v) end end
    function A.reticle(i) set("retLvl", i) end          -- 分划亮度 0 最亮 … 3 最暗
    function A.symb(i) set("symLvl", i) end             -- 符号亮度 0 最亮 … 3 关
    function A.gain(i) set("thGain", i) end             -- 热像增益（对比度）0～4
    function A.level(i) set("thLevel", i) end           -- 热像电平（亮度）0～4
    function A.retNight(i) set("retNight", i == 1) end  -- 分划照明：白天亮红 / 夜里暗红（红分划，钢铁猛兽那样）
    function A.stab(i) set("stab", i == 0) end          -- 稳定器开 / 关
    function A.lrfArm(i) set("arm", i == 0) end         -- 激光测距机待命 / 保险
    function A.lrf(i) set("lrf", (i == 1) and "FIRST" or "LAST") end   -- 末回波 / 首回波
    function A.lrfToggle()
      local st = G.drive
      if st then set("lrf", (st.fcs.lrf == "FIRST") and "LAST" or "FIRST") end
    end
    function A.polaritySet(i)   -- 极性开关：白热 / 黑热（昼光通道开着时先记下，换热像时用）
      local st = G.drive
      if not st then return end
      st.pol = (i == 1) and "BLK" or "WHT"
      if st.mode == 3 or st.mode == 4 then st.mode = (i == 1) and 4 or 3 end
      if G.driveApplySight then G.driveApplySight() end
    end
    function A.thermalSet(i)   -- 视野选择：昼光 / 热像（极性照极性开关）
      local st = G.drive
      if not st then return end
      st.mode = (i == 1) and ((st.pol == "BLK") and 4 or 3) or 1
      if G.sightPref then G.sightPref[(G.isNight and G.isNight()) and "night" or "day"] = st.mode end
      if G.driveApplySight then G.driveApplySight() end
    end
    function A.zoomSet() A.zoom() end
    function A.ammoIdx(i) A.ammo(AMMO4[(i or 0) + 1] or "SABOT") end
    function A.fcsSet(i) A.fcsMode((i or 0) + 1) end
    function A.battlesight() if G.driveBattlesight then G.driveBattlesight() end end
    function A.mrs()
      if G.driveMrs then G.driveMrs() end
      c.mrsT = os.clock()
    end
    function A.bore(daz, del) if G.driveBore then G.driveBore(daz, del) end end   -- 校炮偏差（密位）；都给 nil 归零
    function A.bsRange(key, m) if G.driveBsRange then G.driveBsRange(key, m) end end
    function A.bit()   -- 火控自检：计算机 / 炮长控制显示面板跑一遍自检页，所有指示灯亮一遍
      c.bitT = os.clock()
      c.lampT = os.clock() + 3
    end
    -- 车长热像仪激光测距 + 敌情报告：测到的距离写在 CITV 屏上；打到的那一点附近看得见的敌人标给全队（Weapons.lua 的 ACT.vspot）
    function A.citvLase()
      local d = c.data
      if not (d.citvEye and d.citvF) then return end
      local rp = RaycastParams.new()
      rp.FilterType = Enum.RaycastFilterType.Exclude
      local ex = { c.model }
      if G.viewFolder then table.insert(ex, G.viewFolder) end
      local v = G.viewById and G.viewById(c.id)
      if v and v.model then table.insert(ex, v.model) end
      rp.FilterDescendantsInstances = ex
      local res = G.rayFar(d.citvEye, d.citvF * (5000 * S), rp, true)   -- 车长周视镜激光：远处没加载的山坡按地形高度算回波（Stream.lua）
      c.citvRT = os.clock()
      if res then
        local m = (res.Position - d.citvEye).Magnitude / S
        c.citvR = (m >= 50) and math.floor(m / 5 + 0.5) * 5 or nil
        local st = G.drive
        local from = (st and st.root and st.root.Position) or d.citvEye
        if c.citvR then pcall(function() G.R.Act:FireServer("vspot", from, res.Position) end) end
      else
        c.citvR = nil
      end
      if G.sfx then pcall(G.sfx, "uiClick") end
    end
    -- 布雷德利炮长面板：射速（高速 / 低速 / 单发）、武器总开关（保险 / 待发）、武器选择（25 毫米炮 / 并列机枪）
    local ROF = { "HI", "LO", "SS" }
    function A.rof(i)
      local st = G.drive
      if st then st.rof = ROF[(i or 0) + 1] or "HI" end
    end
    function A.armGun(i)
      local st = G.drive
      if st then st.safe = (i == 1) end
    end
    function A.weapon(i) if G.driveWeapon then G.driveWeapon((i or 0) + 1) end end
    -- 可动部件的档位跟着系统状态（Interior 的 stepMovs 每帧问一次）
    function A.sync()
      local st = G.drive
      if not st or not st.fcs then return nil end
      local f = st.fcs
      local BAL = require(game:GetService("ReplicatedStorage"):WaitForChild("Ballistics"))
      local sym = f.am and BAL.AMMO[f.am] and BAL.AMMO[f.am].sym
      local ai = 0
      for i, a in ipairs(AMMO4) do if a == sym then ai = i - 1 end end
      local zi = st.zoom or 1
      return { pol = ((st.mode == 4) or (st.mode ~= 3 and st.pol == "BLK")) and 1 or 0, zoom = zi - 1, vis = ((st.mode or 1) >= 3) and 1 or 0,
        ammo = ai, lrf = (f.lrf == "FIRST") and 1 or 0, fcs = (f.mode or 1) - 1, stab = (st.stab == false) and 1 or 0,
        arm = (f.arm == false) and 1 or 0, retn = st.retNight and 1 or 0,
        rof = (st.rof == "LO") and 1 or ((st.rof == "SS") and 2 or 0), armg = st.safe and 1 or 0, wpn = (st.wi or 1) - 1 }
    end
    function A.engine(on)
      G.interiorEngineOff = not on
      if G.sfx then pcall(G.sfx, on and "gearShift" or "dry") end
    end
    function A.lampTest() c.lampT = os.clock() + 3 end
    function A.ammo(kind)
      c.ammoKind = kind
      -- 炮长控制面板选的弹种也是火控的弹种（Drive.lua：这门炮能打的才换，换了要重新装填）
      local BAL = require(game:GetService("ReplicatedStorage"):WaitForChild("Ballistics"))
      local st = G.drive
      local wid = st and st.d and st.d.weapons and st.d.weapons[st.wi or 1]
      local key = BAL.panelAmmo and BAL.panelAmmo(kind, wid) or BAL.PANEL[kind]   -- 这门炮没有这种就挑同一类的（T-90M 借 99A 的面板）
      if G.driveAmmo and key then G.driveAmmo(key) end
    end
    function A.citvFov(f) c.citvFov = f end
    function A.citvSector(side, deg)   -- 自动扫描扇区的左（1）/ 右（2）边：相对炮塔的度数（右正）
      c.citvSec = c.citvSec or { -60, 60 }
      c.citvSec[side] = deg
      if c.citvSec[1] > c.citvSec[2] then c.citvSec[1], c.citvSec[2] = c.citvSec[2], c.citvSec[1] end
    end
    function A.citvMode(m) c.citvMode = m end
    return A
  end

  -- 镜头正中间那条线对准的按键：视线和按键正面（−Z 那面，对着人）求交，正面的范围放大一点好对准（左右放大得少：
  --   多功能显示器边上的键只隔 3 厘米）；几个都对得上就挑离键中心最近的（以前按方块求交，斜着看会先碰到旁边那个键的厚度）
  local hover = nil
  local function pickKey(c)
    local o = cam.CFrame.Position
    local dir = cam.CFrame.LookVector
    local best, bs, bt = nil, math.huge, math.huge
    for _, k in ipairs(c.b.softkeys) do
      local cf, sz = k.part.CFrame, k.part.Size * 0.5
      local lo, ld = cf:PointToObjectSpace(o), cf:VectorToObjectSpace(dir)
      if ld.Z > 1e-4 then
        local t = (-sz.Z - lo.Z) / ld.Z
        if t > 0 and t < 1.6 * S then
          local px, py = lo.X + ld.X * t, lo.Y + ld.Y * t
          local mx, my = sz.X + 0.006 * S, sz.Y + 0.010 * S
          if math.abs(px) <= mx and math.abs(py) <= my then
            local score = (px / mx) ^ 2 + (py / my) ^ 2
            if score < bs then best, bs, bt = k, score, t end
          end
        end
      end
    end
    return best, bt
  end
  -- 可动部件（InteriorKit 的 B:mov：旋钮、拨动开关、按钮、握把上的按钮……用户 11-22「所有可动部件都要能动，我准心移动到哪点一下就能动」；
  --   11-24「按钮什么的实现功能」）：视线穿过它的点选盒（hit：组里的盒子，米）就算对准，挑最近的
  local function movBox(mv)
    return mv.g.world * Kit.toS(mv.hit.cf), mv.hit.size * (S / 2)
  end
  local function pickMov(c)
    local o = cam.CFrame.Position
    local dir = cam.CFrame.LookVector
    local best, bt = nil, math.huge
    for _, mv in ipairs(c.b.movs or {}) do
      if mv.hit and mv.g.world then
        local cf, h = movBox(mv)
        local lo, ld = cf:PointToObjectSpace(o), cf:VectorToObjectSpace(dir)
        local t0, t1 = -math.huge, math.huge
        local ok = true
        for _, ax in ipairs({ "X", "Y", "Z" }) do
          local a, dd, e = lo[ax], ld[ax], h[ax]
          if math.abs(dd) < 1e-6 then
            if math.abs(a) > e then ok = false break end
          else
            local ta, tb = (-e - a) / dd, (e - a) / dd
            if ta > tb then ta, tb = tb, ta end
            t0, t1 = math.max(t0, ta), math.min(t1, tb)
            if t0 > t1 then ok = false break end
          end
        end
        if ok and t1 > 0 and t0 < 1.6 * S and t0 < bt then best, bt = mv, math.max(t0, 0) end
      end
    end
    return best, bt
  end
  -- 可动部件的零件（高亮用）：在它的组或者子组里的
  local function movParts(c, mv)
    if mv.parts then return mv.parts end
    mv.parts = {}
    for _, it in ipairs(c.b.parts) do
      local g = it[2]
      while g do
        if g == mv.g or (mv.g.parent and g == mv.g.parent and mv.kind == "hinge") then table.insert(mv.parts, it[1]) break end
        g = g.parent
      end
    end
    return mv.parts
  end
  local function movHover(c, mv, on)
    for _, p in ipairs(movParts(c, mv)) do
      if on then
        p:SetAttribute("C0", p:GetAttribute("C0") or p.Color)
        p.Color = RGB(255, 190, 60)
      elseif p:GetAttribute("C0") then
        p.Color = p:GetAttribute("C0")
        p:SetAttribute("C0", nil)
      end
    end
  end
  local function movText(mv)
    local lb = mv.label and T(mv.label[1], mv.label[2]) or T("开关", "switch")
    local names = mv.posNames
    if names and names[mv.state + 1] then lb = lb .. "：" .. names[mv.state + 1] end
    return lb
  end
  -- 按一下：转一档 / 拨一下 / 按下去，再调它的动作（act[on](新的档位, 这一件)）
  local function movPress(c, mv)
    if mv.kind == "knob" then mv.state = (mv.state + 1) % math.max(1, mv.n or 2)
    elseif mv.kind == "hinge" or mv.kind == "slide" then mv.state = 1 - mv.state
    elseif mv.kind == "push" then mv.pt = 0 end
    mv.held = os.clock() + 0.6   -- 刚拨过：这一会儿不按系统状态回拨（动作还没生效的那一帧）
    if G.sfx then pcall(G.sfx, (mv.kind == "push") and "uiClick" or "dry") end
    local f = mv.on and c.env.act[mv.on]
    if f then
      local ok, err = pcall(f, mv.state, mv)
      if not ok then warn("[内饰] " .. tostring(mv.on) .. "：" .. tostring(err)) end
    end
    for _, s2 in ipairs(c.b.screens) do s2.nextT = 0 end
  end
  -- 每帧：档位跟着系统状态（同一个功能别处也能改：V 键换热像、面板上的键……）、动画走到档位上
  local function stepMovs(c, dt)
    local list = c.b.movs
    if not list then return end
    local sy = c.env.act.sync and c.env.act.sync() or nil
    for _, mv in ipairs(list) do
      if sy and mv.sync and sy[mv.sync] ~= nil and not (mv.held and os.clock() < mv.held) then
        local v = sy[mv.sync]
        if mv.kind == "knob" then mv.state = v % math.max(1, mv.n or 2) else mv.state = v end
      end
      local u
      if mv.kind == "push" then
        if mv.pt then
          mv.pt += dt
          local k = mv.pt / mv.t
          u = (k < 0.5) and (k * 2) or math.max(0, 2 - k * 2)
          if k >= 1 then mv.pt, u = nil, 0 end
        else u = 0 end
        c.b:setAnim(mv.name, CF(mv.axis * ((mv.d or 0.004) * u)))
      else
        mv.p = mv.p or mv.state
        mv.p += (mv.state - mv.p) * math.min(1, dt / math.max(mv.t, 0.02) * 2.5)
        if mv.kind == "knob" then
          c.b:setAnim(mv.name, CFrame.fromAxisAngle(mv.axis, -rad((mv.step or 40) * mv.p)))
        elseif mv.kind == "hinge" then
          c.b:setAnim(mv.name, CFrame.fromAxisAngle(mv.axis, rad((mv.a0 or 0) + ((mv.a1 or -60) - (mv.a0 or 0)) * mv.p)))
        elseif mv.kind == "slide" then
          c.b:setAnim(mv.name, CF(mv.axis * ((mv.d or 0.05) * mv.p)))
        elseif mv.kind == "fn" and mv.fn then
          c.b:setAnim(mv.name, mv.fn(mv.p))
        end
      end
    end
  end
  -- 准心对着的有按键的屏幕（显示面 + 外面一圈边框、按键、按键下面印的字）：左键当成在操作屏幕，不开炮
  --   （用户 11-22：「我操控显示屏的时候坦克会开炮，因为我点了鼠标左键」——原来只有小点正好落在某个键上才不开炮，
  --   点在键旁边、键下面的字上、屏幕上，炮就打出去了）；平显的组合玻璃不算（透过它瞄准开火）
  local hoverScr = nil
  local function pickScreen(c)
    local o = cam.CFrame.Position
    local dir = cam.CFrame.LookVector
    for _, s in ipairs(c.b.screens) do
      local p = s.part
      if p and s.opt and s.opt.keys and (not s.opt.noBack or s.opt.propShell) then   -- 真模型外壳的屏幕（B:propScreen）也算
        local cf, sz = p.CFrame, p.Size * 0.5
        local lo, ld = cf:PointToObjectSpace(o), cf:VectorToObjectSpace(dir)
        if ld.Z > 1e-4 then
          local t = (-sz.Z - lo.Z) / ld.Z
          if t > 0 and t < 1.6 * S then
            local px, py = lo.X + ld.X * t, lo.Y + ld.Y * t
            local m = (s.opt.pickM or ((s.opt.propShell and 0.05 or s.opt.bezel or 0.036) + 0.02)) * S   -- 真模型外壳：键在玻璃外面好几厘米；pickM 自己给（车长显示单元的键盘离屏幕十几厘米）
            if math.abs(px) <= sz.X + m and math.abs(py) <= sz.Y + m then return s end
          end
        end
      end
    end
    return nil
  end
  -- 开着观瞄设备（武器站左键就是开火）、瞄准镜的时候不算：hover 停在进镜前那一帧的值
  G.interiorHover = function() return (hover ~= nil or hoverScr ~= nil) and mode == "seat" and optic == nil and not (G.drive and G.drive.sight) end
  G.interiorHoverKey = function() return hover end   -- 测试用
  -- 测试用：可动部件（旋钮、开关、按钮）的列表；按 id（InteriorAbrams 的 KNOBS：POL、VIS、FCS……）拨一下，走跟左键一样的路
  G.interiorMovs = function() return cur and cur.b.movs or {} end
  G.interiorMovPress = function(id)
    if not cur then return false end
    for _, mv in ipairs(cur.b.movs or {}) do
      if mv.id == id then movPress(cur, mv) return true end
    end
    return false
  end
  local dot = Instance.new("Frame")
  dot.AnchorPoint = Vector2.new(0.5, 0.5)
  dot.Position = UDim2.fromScale(0.5, 0.5)
  dot.Size = UDim2.fromOffset(5, 5)
  dot.BackgroundColor3 = RGB(255, 255, 255)
  dot.BackgroundTransparency = 0.35
  dot.BorderSizePixel = 0
  dot.Visible = false
  dot.Parent = gui
  do
    local cr = Instance.new("UICorner")
    cr.CornerRadius = UDim.new(0.5, 0)
    cr.Parent = dot
  end
  local tip = Instance.new("TextLabel")
  tip.AnchorPoint = Vector2.new(0.5, 0)
  tip.Position = UDim2.new(0.5, 0, 0.5, 14)
  tip.Size = UDim2.fromOffset(520, 40)
  tip.BackgroundTransparency = 1
  tip.TextColor3 = RGB(255, 226, 150)
  tip.TextStrokeTransparency = 0.3
  tip.Font = Enum.Font.BuilderSansMedium
  tip.TextSize = 14
  tip.TextWrapped = true
  tip.Visible = false
  tip.Parent = gui
  local function stepKeys(c)
    local k, kt = nil, math.huge
    local mv, mt = nil, math.huge
    if mode == "seat" and not scopePhase() then
      k, kt = pickKey(c)
      mv, mt = pickMov(c)
      kt = kt or math.huge
      if k and mv then   -- 键和可动部件都对得上：挑近的
        if mt < kt - 0.01 * S then k = nil else mv = nil end
      end
    end
    if hover and hover ~= k and not hover.mov then hover.part.Color = hover.col end
    if hover and hover.mov and (not mv or hover.mov ~= mv) then movHover(c, hover.mov, false) end
    if mv then
      if not (hover and hover.mov == mv) then movHover(c, mv, true) end
      hover = { mov = mv }
    else
      hover = k
    end
    hoverScr = (mode == "seat" and not scopePhase() and not k and not mv) and pickScreen(c) or nil
    dot.Visible = mode == "seat" and not hideUI
    if mv then
      tip.Text = movText(mv) .. "  ——  " .. T("左键：", "click: ") .. ((mv.kind == "knob") and T("转一档", "next position") or ((mv.kind == "push") and T("按下", "press") or T("拨动", "flip")))
      tip.Visible = not hideUI
    elseif k then
      k.part.Color = RGB(255, 190, 60)
      local id = Screens.canon(k.label)
      tip.Text = k.label .. "  ——  " .. (Screens.KEYDESC[id] or "")
      tip.Visible = not hideUI
    elseif hoverScr then   -- 对着屏幕、没对准键：提示怎么按（这时左键不开炮）
      tip.Text = T("小点对准屏幕边的按键再按左键（对着屏幕时左键不开炮）", "put the dot on a key to press it (no firing while looking at a screen)")
      tip.Visible = not hideUI
    else
      tip.Visible = false
    end
  end

  ---------------------------------------------------------------- 镜头

  local function stationCF(c, k)
    local sp = c.spec.stations[k]
    if not sp then return nil end
    local g = c.b.groups[sp.g] or c.b.groups.turret
    local base = CFrame.lookAt(Vector3.zero, sp.look or V(0, 0, -1))
    return g.world * CF(sp.eye * S) * base, sp
  end

  local function enterStation(c, k)
    if not c.spec.stations[k] then return end
    station = k
    mode = "seat"
    c.mine = c.spec.stations[k].crew
    lastStation[c.key] = k
    look.yaw, look.pitch = 0, 0
    title.Text = stationName(k)
    title.Visible = not hideUI
    title.TextTransparency = 0
    c.titleT = os.clock()
  end

  local function setCamera(c, dt)
    local md = UIS:GetMouseDelta()
    local sens = 0.0035 * (look.fov / 72)
    shake = math.max(0, shake - dt * 3)
    local sh = CF()
    if shake > 0 then
      local t = os.clock()
      local k = shake * shake
      sh = CF(math.noise(t * 31, 1) * 0.06 * k, math.noise(t * 29, 2) * 0.06 * k, 0) * ANG(math.noise(t * 23, 3) * 0.025 * k, math.noise(t * 19, 4) * 0.02 * k, 0)
    end
    look.fov += (look.fovT - look.fov) * math.min(1, dt * 10)
    if mode == "seat" then
      local base, sp = stationCF(c, station)
      if not base then return end
      if c.lo and sp.crew == "loader" then   -- 坐在装填手位上装弹：镜头跟着装填手转身、弯腰
        local L = c.lo
        local yaw = L.a.yaw + (L.b.yaw - L.a.yaw) * L.u
        local eye = L.a.eye:Lerp(L.b.eye, L.u)
        base = c.b.groups.turret.world * CF(eye * S) * ANG(0, rad(yaw), 0) * ANG(rad(-16), 0, 0)
      end
      look.yaw = clamp(look.yaw - md.X * sens, -rad(sp.yaw or 120), rad(sp.yaw or 120))
      look.pitch = clamp(look.pitch - md.Y * sens, -rad(sp.down or 60), rad(sp.up or 45))
      local cf = base * ANG(0, look.yaw, 0) * ANG(look.pitch, 0, 0)
      cam.CFrame = cf * sh
    elseif mode == "free" then
      local g = c.b.groups.hull
      free.yaw -= md.X * sens
      free.pitch = clamp(free.pitch - md.Y * sens, -1.45, 1.45)
      local rot = ANG(0, free.yaw, 0) * ANG(free.pitch, 0, 0)
      local mv = V((UIS:IsKeyDown(Enum.KeyCode.Right) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.Left) and 1 or 0),
        (UIS:IsKeyDown(Enum.KeyCode.PageUp) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.PageDown) and 1 or 0),
        (UIS:IsKeyDown(Enum.KeyCode.Down) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.Up) and 1 or 0))
      local spd = (UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)) and 0.8 or 3.5
      free.p += rot:VectorToWorldSpace(V(mv.X, 0, mv.Z)) * spd * dt + V(0, mv.Y * spd * dt, 0)
      cam.CFrame = g.world * CF(free.p) * rot * sh
    end
    cam.FieldOfView = look.fov
  end

  ---------------------------------------------------------------- 每帧

  G.interiorOn = function() return mode ~= nil and cur ~= nil and cur.model ~= nil and cur.model.Parent ~= nil end
  -- 全真模式（TechUI.lua 每半秒查一次）：车外的时候直接坐进这辆车的第一个乘员位；这辆车没有内饰返回 false（调用的改开瞄准镜）
  G.interiorEnterSeat = function()
    if mode ~= nil then return true end
    if not cur then return false end
    mode = "seat"
    enterStation(cur, lastStation[cur.key] or cur.spec.order[1])
    return true
  end
  G.interiorState = function() return { mode = mode, station = station, cur = cur } end   -- 测试用

  function G.stepInterior(dt)
    local fst = G.fly
    if fst and fst.d then   -- 开飞机：座舱（下面 stepAir）；坐后座不开飞机的、遥控无人机的没有
      if cur and not cur.spec.air then teardown() end
      if fst.pilot and not fst.uav and Defs[fst.d.id] and fpAllowed(fst.d.id) then return stepAir(dt, fst) end
      if cur then teardown() end
      return
    end
    local st = G.drive
    if not st or not st.d then
      if cur then teardown() end
      return
    end
    if cur and cur.spec.air then teardown() end
    if not prewarmed and G.opticPrewarm then prewarmed = true G.opticPrewarm(IP_KEYS) end   -- 一上车就在后台把真模型部件生成好
    local v = G.viewById and G.viewById(st.id)
    if not v or not v.hullF then return end
    if cur and cur.id ~= st.id then teardown() end
    -- 进车时真模型部件还没生成好（用了零件拼的）：等它们都好了重建一次内饰（只在没开观瞄设备的时候换，换完回到原来的乘员位）
    if cur and not cur.propsDone and (cur.b.propMiss or cur.headMiss) and not optic then
      local ready = true
      for k in pairs(cur.b.propMiss or {}) do if not (G.opticReady and G.opticReady(k)) then ready = false break end end
      if ready and cur.headMiss then
        for _, k in ipairs({ "ip_cvc", "ip_tsh" }) do if G.opticFailed and not G.opticFailed(k) and not (G.opticReady and G.opticReady(k)) then ready = false end end
      end
      if ready then
        local keepM, keepS = mode, station
        teardown()
        mode, station = keepM, keepS   -- 下一帧照原来的乘员位重建
        return
      else
        cur.propCheckT = (cur.propCheckT or 0) + dt
        if cur.propCheckT > 60 then cur.propsDone = true end   -- 一分钟还没好（没开 Mesh API、生成失败）：不等了
      end
    end
    if mode == nil then
      if cur and cur.model.Parent then cur.model.Parent = nil end
      if cur then extHide(cur, false) end
      hint.Visible, dot.Visible, tip.Visible = false, false, false
      return
    end
    if not cur then
      Kit.headMiss = nil
      cur = build(st, v)
      if not cur then mode = nil return end
      cur.headMiss = Kit.headMiss
      if not cur.b.propMiss and not cur.headMiss then cur.propsDone = true end
      local want = station or lastStation[cur.key]
      if not (want and cur.spec.stations[want]) then want = cur.spec.order[1] end   -- 这型车没有那个乘员位
      enterStation(cur, want)
      for i, g in ipairs(cur.spec.glass or {}) do scratches(g, i * 613 + #cur.key) end   -- 驾驶室的风挡、侧窗：划痕、污渍
      local ammo = G.S and G.S.veh and G.S.veh.ammo
      local wid = st.d.weapons and st.d.weapons[1]
      local resv = (ammo and wid and ammo[wid]) and (ammo[wid][2] or 0) or 34
      if cur.spec.loader == "carousel" then syncCarousel(cur, math.min(22, resv)) else syncRack(cur, math.min(36, resv)) end
    end
    if quickOptic and mode == "seat" and cur then   -- T 从车外直接进车长的主观瞄（下面按键那里记下的）
      quickOptic = false
      if cur.spec.lock then   -- 坦克锁在炮长位：车长的主观瞄在炮长位的 T（第三个）上
        if station ~= cur.spec.lock then enterStation(cur, cur.spec.lock) end   -- 车外按 T 记下的是车长位（内饰早就建好时不经过 enterStation）
        local sp = cur.spec.stations[cur.spec.lock]
        local slot = (sp and sp.optics and sp.optics.third) and "third" or "primary"
        if enterOptic(cur, slot) and optic then optic.quick = true end
      else
        if station ~= "commander" and cur.spec.stations.commander then enterStation(cur, "commander") end
        if enterOptic(cur, "primary") and optic then optic.quick = true end
      end
    end
    local c = cur
    -- 乘员位、观瞄设备里：外模型不画（挖了内腔的车乘员位上照画）；导演镜头：画。
    --   主瞄准镜（st.sight）也按观瞄设备算（全藏）。Drive 开镜 / 退镜时自己把整车零件设成藏 / 不藏（ownVisible），extHide 记着的状态就不对了：
    --   镜子状态一变，缓存作废、按现在的乘员位重新藏一遍——原来退镜以后整辆车的外模型、原模型的简易内饰全露出来，
    --   乘员眼前、车里的显示屏前面横着一块块外壳（用户 11-24：「开镜有bug……屏幕有一块色斑」）
    local sightNow = st.sight == true
    if c.sightWas ~= sightNow then c.sightWas, c.extHidden = sightNow, nil end
    extHide(c, mode == "seat" or optic ~= nil or sightNow, optic ~= nil or sightNow)
    -- 别的观瞄设备：内饰收起来，镜头在镜子里（辅助瞄准镜同时开着 Drive 的瞄准镜，炮跟着鼠标瞄）
    if optic then
      if c.model.Parent then c.model.Parent = nil end
      frames(c, v)
      stepAnim(c, v, st, dt)
      frames(c, v)
      gather(c, v, st)
      stepOptic(c, dt)
      hint.Visible = not hideUI
      if optic.o.rws then
        hint.Text = T("T 退出 · 鼠标转武器站 · 左键开火（12.7 毫米）· 滚轮换视场", "T exit · mouse to slew the RWS · LMB fire (12.7 mm) · wheel FOV")
      else
        hint.Text = T("Shift / G / T 退出观瞄 · 滚轮换视场 · 鼠标转镜子", "Shift / G / T exit optic · wheel FOV · mouse to traverse")
      end
      dot.Visible, tip.Visible = false, false
      return
    end
    -- 瞄准镜里：内饰收起来，镜头归 Drive
    if st.sight then
      if c.model.Parent then c.model.Parent = nil end
      hint.Visible = false
      return
    end
    if not c.model.Parent then c.model.Parent = workspace end
    G.interiorNow = c.model   -- 车内的零件：开车的测距 / 瞄准射线不算它（Drive.lua rayEx）
    frames(c, v)            -- 先按上一帧的动画算一遍（动画里要用到各组的位置）
    stepAnim(c, v, st, dt)
    stepMovs(c, dt)         -- 旋钮、开关、按钮
    frames(c, v)            -- 动画改了子组，再算一遍
    stepRound(c)
    pose(c)
    if not stepScope(c, dt) then setCamera(c, dt) end
    stepKeys(c)
    stepCrew(c, cam.CFrame.LookVector)
    stepScreens(c, v, st)
    -- 弹架跟着备弹数（服务器扣了备弹、补给车补了弹）
    local ammo = G.S and G.S.veh and G.S.veh.ammo
    local wid = st.d.weapons and st.d.weapons[1]
    if ammo and wid and ammo[wid] and not c.loadT then
      if c.spec.loader == "carousel" then
        -- 自动装弹机里的数：打一发少一个；补给车补了弹（备弹多了）才补满
        local resv = ammo[wid][2] or 0
        if c.resv0 and resv > c.resv0 then c.carN = math.min(22, resv) end
        c.resv0 = resv
        local n = math.min(c.carN or 22, resv)
        if n ~= c.rackN then syncCarousel(c, n) end
      else
        local n = math.min(36, ammo[wid][2] or 0)
        if n ~= c.rackN then syncRack(c, n) end
      end
    end
    -- 提示
    if c.titleT and os.clock() - c.titleT > 2.5 then
      title.TextTransparency = math.min(1, (os.clock() - c.titleT - 2.5) / 0.8)
      if title.TextTransparency >= 1 then title.Visible = false c.titleT = nil end
    end
    hint.Visible = not hideUI
    if mode == "free" then
      hint.Text = T("导演镜头：方向键移动 · PageUp/PageDown 升降 · Ctrl 慢 · 滚轮变焦 · B 回乘员位 · U 藏界面",
        "FREE CAM: arrows move · PgUp/PgDn up/down · Ctrl slow · wheel zoom · B back to seat · U hide UI")
    else
      local LB = { driver = { "驾驶员", "driver" }, gunner = { "炮长", "gunner" }, commander = { "车长", "commander" }, loader = { "装填手", "loader" }, troop = { "载员", "troop" } }
      local fk = {}
      local FN = { driver = 2, gunner = 3, commander = 4, loader = 5 }
      local named = c.spec.lock ~= nil   -- 坦克：F2～F5 按名字（驾驶员 / 炮长 / 车长 / 装填手）；别的车按乘员位顺序
      for i, k2 in ipairs(c.spec.order) do
        local lb = LB[k2] or { k2, k2 }
        table.insert(fk, "F" .. ((named and FN[k2]) or (i + 1)) .. " " .. T(lb[1], lb[2]))
      end
      local tk = (st and st.d and st.d.turret) and T("方向键转炮塔、抬压炮 · WASD 开车 · ", "arrows traverse / elevate · WASD drive · ") or ""
      hint.Text = tk .. T("C 车外 · " .. table.concat(fk, "  ") .. " · Shift / G / T 观瞄设备 · B 导演镜头 · L 车内灯 · U 藏界面 · 滚轮变焦",
        "C exterior · " .. table.concat(fk, "  ") .. " · Shift / G / T optics · B free cam · L lights · U hide UI · wheel zoom")
    end
  end

  ---------------------------------------------------------------- 开镜：头凑到目镜上 + 目镜的光学效果
  -- 用户 11-21：第一人称开镜就是把视角移动到观瞄镜，镜子要有光学效果——从黑慢慢滑到不黑，看倍镜会有的效果
  --   开镜：坐在炮长位上时镜头先 0.22 秒凑到目镜上（车里照常画），再真的切进瞄准镜；
  --   切进去以后：先全黑，亮的圆从偏下偏左的地方滑到正中间、一边变大（眼睛找出瞳的样子），边缘几圈渐暗；
  --   开着镜猛转的时候圆跟着往反方向偏一点，一边露出黑的月牙（眼睛和目镜没对正），慢慢回正
  --   退镜：镜头从目镜往回抬到乘员位
  local sfx = Instance.new("ScreenGui")
  sfx.Name = "ScopeFx"
  sfx.ResetOnSpawn = false
  sfx:SetAttribute("Fx", true)
  sfx.IgnoreGuiInset = true
  sfx.DisplayOrder = 30
  sfx.Enabled = false
  sfx.Parent = gui.Parent
  local black = Instance.new("Frame")
  black.Size = UDim2.fromScale(1, 1)
  black.BackgroundColor3 = RGB(0, 0, 0)
  black.BorderSizePixel = 0
  black.Parent = sfx
  local holes = {}
  -- 用户 11-27「光学渐变也有些生硬」：原来 4 圈 10 像素、一档一档的暗边（看得出一道道环）——改成 16 圈挨着的细环、外暗内淡，渐暗连成一片
  local NRING = 16
  for i = 1, NRING do   -- 一个透明的圆，外面一圈极粗的黑描边盖住圆外面；里面一圈圈细的半透明描边做出渐暗的边
    local h = Instance.new("Frame")
    h.AnchorPoint = Vector2.new(0.5, 0.5)
    h.BackgroundTransparency = 1
    h.Parent = sfx
    local cr = Instance.new("UICorner")
    cr.CornerRadius = UDim.new(0.5, 0)
    cr.Parent = h
    local sk = Instance.new("UIStroke")
    sk.Color = RGB(0, 0, 0)
    sk.Thickness = (i == 1) and 4000 or 9
    sk.Transparency = (i == 1) and 0 or (0.8 + 0.19 * (i - 2) / (NRING - 2))
    sk.Parent = h
    holes[i] = { f = h, k = 1 - (i - 1) * 0.012, sk = sk }
  end
  local scope = { phase = nil, t = 0, cb = nil, iris = nil, off = Vector2.new(), on = false }
  scopePhase = function() return scope.phase ~= nil end
  local function startIris()
    scope.iris = 0
    scope.off = Vector2.new(-0.16, 0.10)
    sfx.Enabled = true
  end
  G.interiorScope = function(want, cb)
    local st = G.drive
    if not st or G.myVeh ~= st then return false end
    local sp = cur and station and cur.spec.stations[station]
    -- 别的观瞄设备开着：Shift 退出它
    if optic then
      exitOptic(cur)
      return true
    end
    -- 这个位置的主镜不是炮长主瞄准镜（驾驶员的 DVE、车长的热像仪、装填手潜望镜……）：开它
    if want and mode == "seat" and sp and sp.optics and sp.optics.primary and sp.optics.primary.kind ~= "gps" and cur.model.Parent then
      enterOptic(cur, "primary")
      return true
    end
    if want then
      if mode == "seat" and sp and sp.sight and cur.model.Parent then
        scope.phase, scope.t, scope.cb = "in", 0, cb
        return true
      end
      cb()
      startIris()
      return true
    elseif mode == "seat" and sp then
      cb()
      scope.phase, scope.t = "out", 0
      sfx.Enabled = false
      return true
    end
    sfx.Enabled = false
    return false
  end
  local function scopeEye(c)
    local sp = c.spec.stations[station]
    if not sp then return nil end
    local g = c.b.groups[sp.g] or c.b.groups.turret
    local gun = c.b.groups.gun.world
    local p = g.world * ((sp.scope or sp.eye) * S)
    return CFrame.lookAt(p, p + gun.LookVector, g.world.UpVector)
  end
  -- 每帧：凑过去 / 抬起来的镜头（stepInterior 里调，返回 true 表示这一帧镜头归它）
  stepScope = function(c, dt)
    if scope.phase == "in" then
      scope.t += dt
      local u = sm(scope.t / 0.22)
      local from = stationCF(c, station)
      local to = scopeEye(c)
      if from and to then
        local base = from * ANG(0, look.yaw, 0) * ANG(look.pitch, 0, 0)
        cam.CFrame = base:Lerp(to, u)
        cam.FieldOfView = look.fov + (40 - look.fov) * u
      end
      if scope.t >= 0.22 then
        scope.phase = nil
        local cb = scope.cb
        scope.cb = nil
        if cb then cb() end
        startIris()
      end
      return true
    elseif scope.phase == "out" then
      scope.t += dt
      local u = sm(scope.t / 0.28)
      local from = scopeEye(c)
      local to = stationCF(c, station)
      if from and to then
        look.yaw, look.pitch = 0, 0
        cam.CFrame = from:Lerp(to, u)
        cam.FieldOfView = 40 + (look.fov - 40) * u
      end
      if scope.t >= 0.28 then scope.phase = nil end
      return true
    end
    return false
  end
  G.frameConn("ScopeFx", function(dt)
    local st = G.drive
    local inSight = (st and st.sight and G.myVeh == st) or optic ~= nil
    if not inSight then
      if sfx.Enabled and not scope.iris then sfx.Enabled = false end
      if not inSight then scope.iris = nil sfx.Enabled = false end
      return
    end
    -- 用户 11-27（照战雷的开镜截图）：车外的炮长瞄准镜是全屏的——开镜那一下（先黑、亮圆滑进来变大）照旧放，放完就把边上那几圈暗角撤掉；
    --   车里的观瞄设备（optic：车长热像仪、备用镜……）照旧有目镜的效果
    if optic == nil then
      -- 车外的炮长瞄准镜（全屏，照战雷）：开镜只从黑平滑淡入 0.2 秒，不放亮圆、不留暗边（用户 11-27「光学渐变也有些生硬」）
      if scope.iris then
        scope.iris += dt
        black.BackgroundTransparency = math.clamp(scope.iris / 0.2, 0, 1)
        for _, h in ipairs(holes) do if h.f.Visible then h.f.Visible = false end end
        sfx.Enabled = true
        if scope.iris >= 0.2 then scope.iris = nil end
      elseif sfx.Enabled then
        sfx.Enabled = false
      end
      return
    end
    for _, h in ipairs(holes) do if not h.f.Visible then h.f.Visible = true end end   -- 车里的观瞄设备：目镜的圆和暗边
    local vp = cam.ViewportSize
    local R = math.sqrt(vp.X * vp.X + vp.Y * vp.Y) / 2 * 1.02
    local md = UIS:GetMouseDelta()
    -- 猛转：圆往反方向偏（眼睛没跟上目镜），慢慢回正
    scope.off = scope.off + Vector2.new(-md.X, -md.Y) / math.max(vp.Y, 1) * 0.35
    if scope.off.Magnitude > 0.25 then scope.off = scope.off.Unit * 0.25 end
    scope.off = scope.off * math.exp(-dt * ((scope.iris and 4.5) or 6))
    local r = R
    if scope.iris then
      scope.iris += dt
      local t = scope.iris
      black.BackgroundTransparency = (t < 0.08) and 0 or 1
      local u = clamp((t - 0.08) / 0.45, 0, 1)
      local e = 1 - (1 - u) ^ 3
      r = R * (0.06 + 0.94 * e)
      if t > 0.6 then scope.iris = nil end
    else
      black.BackgroundTransparency = 1
    end
    sfx.Enabled = true
    local cx, cy = vp.X / 2 + scope.off.X * vp.Y, vp.Y / 2 + scope.off.Y * vp.Y
    for _, h in ipairs(holes) do
      local rr = r * h.k
      h.f.Position = UDim2.fromOffset(cx, cy)
      h.f.Size = UDim2.fromOffset(rr * 2, rr * 2)
    end
  end)
  G.interiorScopeState = function() return scope end   -- 测试用

  ---------------------------------------------------------------- 其他观瞄设备（各乘员位的主镜 / 备用镜）
  -- 资料对照：M1A2 SEPv2——炮长主瞄准镜 GPS（Drive.lua）、炮长辅助瞄准镜 GAS（M920，8 倍直瞄望远镜，主镜坏了用，分划按弹种刻距离）、
  --   车长独立热像仪 CITV（宽 / 窄视场，能自己转，猎-歼）、主瞄准镜延伸目镜 GPSE（车长看炮长的画面）、CROWS-LP 遥控武器站摄像头、
  --   驾驶员视觉增强器 DVE（AN/VAS-5 非制冷热像，车头方向）、后视热像摄像头 RVSS、装填手潜望镜（能 360° 转）；
  --   99A——炮长主镜 / 备用瞄准镜、车长周视瞄准镜（昼夜两用，独立转，猎-歼）、驾驶员微光夜视潜望镜
  --   Shift：本位主镜；G：备用镜；T：第三个（M1A2 车长的 CROWS）；滚轮换视场；能转的镜子用鼠标转；再按一次退出
  optic = nil
  local og = Instance.new("ScreenGui")
  og.Name = "Optic"
  og.ResetOnSpawn = false
  og:SetAttribute("Fx", true)
  og.IgnoreGuiInset = true
  og.DisplayOrder = 24
  og.Enabled = false
  og.Parent = gui.Parent
  local hole = Instance.new("Frame")
  hole.AnchorPoint = Vector2.new(0.5, 0.5)
  hole.Position = UDim2.fromScale(0.5, 0.5)
  hole.BackgroundTransparency = 1
  hole.Parent = og
  local holeCr = Instance.new("UICorner")
  holeCr.Parent = hole
  local holeSk = Instance.new("UIStroke")
  holeSk.Color = RGB(0, 0, 0)
  holeSk.Thickness = 4000
  holeSk.Parent = hole
  local ret = Instance.new("Frame")
  ret.AnchorPoint = Vector2.new(0.5, 0.5)
  ret.Position = UDim2.fromScale(0.5, 0.5)
  ret.BackgroundTransparency = 1
  ret.Parent = og
  local oName = Instance.new("TextLabel")
  oName.BackgroundTransparency = 1
  oName.Font = Enum.Font.RobotoMono
  oName.TextSize = 16
  oName.TextXAlignment = Enum.TextXAlignment.Left
  oName.Parent = og
  local oInfo = oName:Clone()
  oInfo.TextXAlignment = Enum.TextXAlignment.Right
  oInfo.Parent = og
  local grainL = {}
  for i = 1, 8 do
    local g = Instance.new("Frame")
    g.BorderSizePixel = 0
    g.BackgroundColor3 = RGB(255, 255, 255)
    g.BackgroundTransparency = 0.94
    g.Size = UDim2.new(1, 0, 0, 1)
    g.Parent = og
    grainL[i] = g
  end
  local icc = Instance.new("ColorCorrectionEffect")
  icc.Enabled = false
  icc.Parent = cam
  local ohl = {}
  local function clearOhl() for _, h in ipairs(ohl) do h:Destroy() end ohl = {} end
  local function hl(adornee, col)
    local h = Instance.new("Highlight")
    h.Adornee = adornee
    h.FillColor, h.OutlineColor = col, col
    h.FillTransparency, h.OutlineTransparency = 0.08, 0.5
    h.DepthMode = Enum.HighlightDepthMode.Occluded
    h.Parent = cam
    table.insert(ohl, h)
  end
  local LOOKS = {
    day = { -0.1, 0.10, 0.0, RGB(255, 255, 255) }, whot = { -1, 0.45, -0.32, RGB(225, 225, 225), Color3.new(1, 1, 1) },
    bhot = { -1, 0.25, 0.22, RGB(235, 235, 235), Color3.new(0, 0, 0) }, nv = { -1, 0.35, 0.10, RGB(120, 255, 140) },
    -- 昼光镜（CROWS 摄像头、辅助瞄准镜、潜望镜）夜里用（用户 11-22：「坦克第三人称驾驶开镜全屏都是黄色」——夜视仪的增亮还留着、
    --   昼光档颜色照原样，沙漠的沙子过曝成满屏的黄）：夜里看出去暗、发灰、偏冷，跟真的昼光镜在夜里一样只看得清个轮廓
    dayN = { -0.7, 0.12, -0.05, RGB(212, 220, 236) },
  }
  local function applyLook(look)
    clearOhl()
    G.opticNv = look == "nv"   -- 夜视档：昼夜（DayNight.lua）照夜视仪那样增亮
    if look == "day" and G.isNight and G.isNight() then look = "dayN" end
    local L = LOOKS[look]
    if not L then icc.Enabled = false return end
    icc.Enabled = true
    icc.Saturation, icc.Contrast, icc.Brightness, icc.TintColor = L[1], L[2], L[3], L[4]
    if L[5] then   -- 热像：车、人亮（黑热是黑的）
      if G.viewFolder then hl(G.viewFolder, L[5]) end
      local n = 0
      for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= me and pl.Character and n < 24 then hl(pl.Character, L[5]) n += 1 end
      end
    end
    for _, g in ipairs(grainL) do g.Visible = look ~= "day" end
  end
  -- 分划（像素，以屏幕中间为原点）：每种镜子一套
  local function rLine(x0, y0, x1, y1, t, col)
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.BorderSizePixel = 0
    f.BackgroundColor3 = col
    local dx, dy = x1 - x0, y1 - y0
    f.Position = UDim2.new(0.5, (x0 + x1) / 2, 0.5, (y0 + y1) / 2)
    f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), t)
    f.Rotation = math.deg(math.atan2(dy, dx))
    f.Parent = ret
    return f
  end
  local function rText(txt, x, y, size, col, align)
    local l = Instance.new("TextLabel")
    l.AnchorPoint = Vector2.new((align == "r") and 1 or ((align == "l") and 0 or 0.5), 0.5)
    l.Position = UDim2.new(0.5, x, 0.5, y)
    l.Size = UDim2.fromOffset(160, size + 4)
    l.BackgroundTransparency = 1
    l.Text = txt
    l.TextSize = size
    l.TextColor3 = col
    l.Font = Enum.Font.RobotoMono
    l.TextXAlignment = (align == "r") and Enum.TextXAlignment.Right or ((align == "l") and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center)
    l.Parent = ret
    return l
  end
  local RETS = {}
  -- GAS（M920）：中间一根竖线，左边脱壳穿甲弹的距离刻度，右边破甲 / 多用途弹的（弹道越弯刻度越疏）
  RETS.gas = function(u, col)
    rLine(0, -u * 0.30, 0, u * 0.42, 2, col)
    rLine(-6, -u * 0.30 - 8, 0, -u * 0.30, 2, col)
    rLine(6, -u * 0.30 - 8, 0, -u * 0.30, 2, col)
    for i = 0, 6 do
      local y = i * u * 0.05
      rLine(-u * 0.06, y, -4, y, 2, col)
      rText(tostring(i * 4), -u * 0.07, y, 13, col, "r")
    end
    for i = 0, 6 do
      local y = i * u * 0.065
      rLine(4, y, u * 0.06, y, 2, col)
      rText(tostring(i * 2), u * 0.07, y, 13, col, "l")
    end
    rText("SABOT", -u * 0.09, -u * 0.06, 13, col, "r")
    rText("HEAT/MPAT", u * 0.09, -u * 0.06, 13, col, "l")
  end
  RETS.gascn = function(u, col)
    rLine(0, -u * 0.30, 0, u * 0.42, 2, col)
    for i = 0, 6 do
      local y = i * u * 0.05
      rLine(-u * 0.06, y, -4, y, 2, col)
      rText(tostring(i * 4), -u * 0.07, y, 13, col, "r")
      local y2 = i * u * 0.065
      rLine(4, y2, u * 0.06, y2, 2, col)
      rText(tostring(i * 2), u * 0.07, y2, 13, col, "l")
    end
    rText("穿甲", -u * 0.09, -u * 0.06, 14, col, "r")
    rText("破甲/榴", u * 0.09, -u * 0.06, 14, col, "l")
  end
  RETS.citv = function(u, col)
    local b = u * 0.07
    rLine(-b, -b, b, -b, 2, col) rLine(-b, b, b, b, 2, col) rLine(-b, -b, -b, b, 2, col) rLine(b, -b, b, b, 2, col)
    rLine(-u * 0.2, 0, -b, 0, 2, col) rLine(b, 0, u * 0.2, 0, 2, col) rLine(0, b, 0, u * 0.18, 2, col)
    rLine(-u * 0.32, -u * 0.36, u * 0.32, -u * 0.36, 1, col)
  end
  RETS.pano = function(u, col)
    rLine(-u * 0.18, 0, -u * 0.02, 0, 2, col) rLine(u * 0.02, 0, u * 0.18, 0, 2, col)
    rLine(0, u * 0.02, 0, u * 0.16, 2, col)
    for i = -4, 4 do if i ~= 0 then rLine(i * u * 0.04, -3, i * u * 0.04, 3, 1, col) end end
    rLine(-u * 0.30, u * 0.36, u * 0.30, u * 0.36, 1, col)
  end
  RETS.crows = function(u, col)
    local g = u * 0.015
    rLine(-u * 0.10, 0, -g, 0, 2, col) rLine(g, 0, u * 0.10, 0, 2, col)
    rLine(0, -u * 0.10, 0, -g, 2, col) rLine(0, g, 0, u * 0.10, 2, col)
    for i = 1, 4 do rLine(-4, g + i * u * 0.02, 4, g + i * u * 0.02, 1, col) end
  end
  RETS.dve = function(u, col)
    local w, h = u * 0.55, u * 0.40
    for _, sx in ipairs({ -1, 1 }) do
      for _, sy in ipairs({ -1, 1 }) do
        rLine(sx * w, sy * h, sx * (w - u * 0.06), sy * h, 2, col)
        rLine(sx * w, sy * h, sx * w, sy * (h - u * 0.06), 2, col)
      end
    end
  end
  RETS.rear = function(u, col)   -- 倒车引导线（近红远绿）
    for _, sx in ipairs({ -1, 1 }) do
      rLine(sx * u * 0.30, u * 0.40, sx * u * 0.14, u * 0.02, 3, RGB(255, 210, 60))
    end
    rLine(-u * 0.26, u * 0.32, u * 0.26, u * 0.32, 2, RGB(255, 80, 60))
    rLine(-u * 0.20, u * 0.18, u * 0.20, u * 0.18, 2, RGB(255, 210, 60))
    rLine(-u * 0.16, u * 0.06, u * 0.16, u * 0.06, 2, RGB(80, 230, 110))
  end
  -- 周视瞄准镜（自行火炮间接瞄准）：十字线、横竖两条米位刻度（每格 10 密位、每 50 一个大刻度带数字）
  RETS.mil = function(u, col)
    rLine(-u * 0.42, 0, u * 0.42, 0, 1, col)
    rLine(0, -u * 0.42, 0, u * 0.42, 1, col)
    for i = -20, 20 do
      if i ~= 0 then
        local x = i * u * 0.02
        local big = i % 5 == 0
        rLine(x, -(big and 8 or 4), x, (big and 8 or 4), 1, col)
        if big then rText(tostring(math.abs(i * 10)), x, 16, 11, col, "c") end
        rLine(-(big and 8 or 4), x, (big and 8 or 4), x, 1, col)
      end
    end
  end
  RETS.none = function() end
  -- 车长的遥控武器站瞄哪：顺着鼠标给的方向打一条射线（不算画出来的车、自己的车和人）
  local rayP = RaycastParams.new()
  rayP.FilterType = Enum.RaycastFilterType.Exclude
  -- 光学设备的镜头位置、朝向
  local function opticCF(c, o)
    local b = c.b
    local g = b.groups[o.g] or b.groups.turret
    local p = g.world * (o.pos * S)
    local up = g.world.UpVector
    local dir
    if o.dir == "gun" then dir = b.groups.gun.world.LookVector
    elseif o.dir == "hull" then dir = b.groups.hull.world.LookVector
    elseif o.dir == "rear" then dir = -b.groups.hull.world.LookVector + b.groups.hull.world.UpVector * -0.12
    elseif o.dir == "citv" then
      local d = c.data
      dir = d.citvF or b.groups.turret.world.LookVector
    elseif o.rws then   -- 车长的遥控武器站（CROWS 的摄像头装在俯仰的托架上）：镜头跟着机枪转、俯仰
      local v = G.viewById and G.viewById(c.id)
      if v and v.rgF then return v.rgF * CF(o.eye or V(-0.6, 0.25, -0.2)) end
      dir = b.groups.gun.world.LookVector   -- 武器站就是炮塔（斯特赖克、M1150……）：摄像头顺着炮塔上的枪
    else   -- free / free360：鼠标转
      local base = b.groups.turret.world
      dir = (base * ANG(0, optic.yaw, 0) * ANG(optic.pitch, 0, 0)).LookVector
    end
    return CFrame.lookAt(p, p + dir, up)
  end
  local function ownHide(c, on) extHide(c, on, true) end
  exitOptic = function(c)
    if not optic then return end
    local o = optic.o
    local prevWi = optic.prevWi
    optic = nil
    G.interiorOptic = nil
    local st = G.drive
    if st and o.rws then   -- 车长松开武器站：武器换回原来那件，机枪又跟着炮长的准星
      if prevWi then st.wi = prevWi end
      st.rwsPt = nil
    end
    og.Enabled = false
    icc.Enabled = false
    G.opticNv = false
    clearOhl()
    if o.useSight and G.driveSetSight then G.driveSetSight(false) end
    if c then ownHide(c, false) end
    look.fovT = 72
  end
  enterOptic = function(c, slot)
    local sp = c.spec.stations[station]
    local o = sp and sp.optics and sp.optics[slot]
    if not o then return false end
    -- 坦克不带机枪（VehDefs.TANK_MG，用户 11-22「坦克不要弄哪个机枪」）：车长的遥控武器站这一位空着，按 T 没反应
    if o.rws and G.drive and G.drive.d and G.drive.d.noRoofMg then return false end
    if o.kind == "gps" then   -- 炮长主瞄准镜（车长看就是延伸目镜）：照常的瞄准镜，头先凑过去
      scope.phase, scope.t, scope.cb = "in", 0, function() if G.driveSetSight then G.driveSetSight(true) end end
      return true
    end
    exitOptic(c)
    optic = { o = o, zi = 1, yaw = 0, pitch = 0, slot = slot }
    G.interiorOptic = o.kind
    if o.useSight and G.driveSetSight then G.driveSetSight(true) end
    local st = G.drive
    if o.rws and st then
      -- 车长的遥控武器站（M1A2 的 CROWS）：开火打的就是它，鼠标转的也是它（st.rwsPt），炮塔还归炮长的准星；
      --   武器站就是炮塔的车（斯特赖克……）鼠标转的是炮塔（st.aimPt）
      for i, wid in ipairs(st.d.weapons) do
        if wid == "hmg" then optic.prevWi = st.wi st.wi = i end
      end
      -- 从机枪现在指的方向接着转；方向记在世界坐标里（武器站有稳定：车身、炮塔怎么转，枪口还指着原来那个方向）
      local v = G.viewById and G.viewById(c.id)
      local l = (st.d.rws and v and v.rgF) and v.rgF.LookVector or c.b.groups.gun.world.LookVector
      optic.yaw, optic.pitch = math.atan2(-l.X, -l.Z), math.asin(clamp(l.Y, -1, 1))
    end
    ownHide(c, true)
    for _, ch in ipairs(ret:GetChildren()) do ch:Destroy() end
    local vp = cam.ViewportSize
    local u = math.min(vp.X, vp.Y)
    -- 昼光镜的黑分划、黑字：夜里画面是暗的（LOOKS.dayN），黑的看不见，换成浅色
    local dayLit = o.look == "day" and not (G.isNight and G.isNight())
    local col = (o.look == "bhot") and RGB(20, 20, 20) or ((o.look == "nv") and RGB(190, 255, 190) or (dayLit and RGB(30, 30, 30) or RGB(235, 240, 235)))
    if o.ret == "crows" or o.ret == "rear" then col = RGB(240, 240, 240) end
    if (o.ret == "gas" or o.ret == "gascn") and dayLit then col = RGB(20, 20, 20) end
    ret.Size = UDim2.fromOffset(0, 0)
    ;(RETS[o.ret] or RETS.none)(u, col)
    -- 镜框形状：圆的目镜、长方形的屏幕、装填手潜望镜的长条
    if o.shape == "circle" then
      holeCr.CornerRadius = UDim.new(0.5, 0)
      hole.Size = UDim2.fromOffset(u * 0.92, u * 0.92)
    elseif o.shape == "slot" then
      holeCr.CornerRadius = UDim.new(0, 6)
      hole.Size = UDim2.fromOffset(u * 1.3, u * 0.36)
    else
      holeCr.CornerRadius = UDim.new(0, 4)
      hole.Size = UDim2.fromOffset(u * 1.2, u * 0.9)
    end
    oName.Position = UDim2.new(0.5, -hole.Size.X.Offset / 2 + 10, 0.5, -hole.Size.Y.Offset / 2 + 6)
    oName.Size = UDim2.fromOffset(300, 20)
    oName.Text = o.name or ""
    oName.TextColor3 = (dayLit and o.shape == "circle") and RGB(20, 20, 20) or RGB(230, 236, 230)
    oInfo.Position = UDim2.new(0.5, hole.Size.X.Offset / 2 - 310, 0.5, -hole.Size.Y.Offset / 2 + 6)
    oInfo.Size = UDim2.fromOffset(300, 20)
    oInfo.TextColor3 = oName.TextColor3
    applyLook(o.look)
    og.Enabled = not hideUI or true
    look.fovT = o.fovs[1]
    look.fov = o.fovs[1]
    startIris()
    return true
  end
  stepOptic = function(c, dt)
    if not optic then return false end
    local o = optic.o
    local md = UIS:GetMouseDelta()
    local sens = 0.0035 * (look.fov / 72)
    if o.rws then   -- 车长的遥控武器站：鼠标给想打的方向，武器站按自己的转速跟过去，镜头跟着机枪（opticCF）
      local st = G.drive
      local R = st and st.d.rws
      optic.yaw -= md.X * sens
      local el = (R and R.elev) or (st and st.d.turret and st.d.turret.elev) or { -20, 60 }
      optic.pitch = clamp(optic.pitch - md.Y * sens, rad(el[1]), rad(el[2]))
      if st then
        local v = G.viewById and G.viewById(c.id)
        local o3 = (v and v.rgF and v.rgF.Position) or c.b.groups.gun.world.Position
        local dir = (ANG(0, optic.yaw, 0) * ANG(optic.pitch, 0, 0)).LookVector   -- 世界坐标里想打的方向
        local ex = { c.model, workspace.CurrentCamera }
        if G.viewFolder then table.insert(ex, G.viewFolder) end
        if st.em then table.insert(ex, st.em) end
        if me.Character then table.insert(ex, me.Character) end
        rayP.FilterDescendantsInstances = ex
        local hit = G.rayFar(o3, dir * 3000, rayP)
        local pt = hit and hit.Position or (o3 + dir * 3000)
        if R then st.rwsPt = pt else st.aimPt = pt end
      end
    elseif o.dir == "free" or o.dir == "free360" then
      optic.yaw -= md.X * sens
      if o.dir == "free" then optic.yaw = clamp(optic.yaw, -rad(170), rad(170)) end
      optic.pitch = clamp(optic.pitch - md.Y * sens, -rad((o.dir == "free360") and 12 or 20), rad((o.dir == "free360") and 12 or 50))
    elseif o.dir == "citv" then   -- 热像仪 / 周视镜：鼠标转镜头（手动扫描）
      local tW = c.b.groups.turret.world
      local cur3 = c.citvMan or V(0, 0, -1)
      local yaw = math.atan2(-cur3.X, -cur3.Z) - md.X * sens
      local pit = math.asin(clamp(cur3.Y, -1, 1)) - md.Y * sens
      pit = clamp(pit, -rad(12), rad(25))
      c.citvMan = (ANG(0, yaw, 0) * ANG(pit, 0, 0)).LookVector
      c.citvMode = "MAN"
      local _ = tW
    end
    local fov = o.fovs[optic.zi] or o.fovs[1]
    look.fov += (fov - look.fov) * math.min(1, dt * 10)
    cam.CFrame = opticCF(c, o)
    cam.FieldOfView = look.fov
    for _, g in ipairs(grainL) do
      g.Position = UDim2.fromOffset(0, math.random(0, math.floor(cam.ViewportSize.Y)))
      g.BackgroundTransparency = 0.88 + math.random() * 0.1
    end
    local d = c.data
    local zt = (#o.fovs > 1) and string.format("  %s", (optic.zi == 1) and "WFOV" or "NFOV") or ""
    oInfo.Text = (d.range and string.format("%04d M", math.floor(d.range)) or "") .. zt
    og.Enabled = true
    return true
  end
  G.interiorOpticState = function() return optic end   -- 测试用

  ---------------------------------------------------------------- 飞机座舱（对标 DCS）
  -- V 进出座舱；头跟着鼠标瞄准的方向转（看哪飞哪，同战雷的座舱视角），大过载时头被甩；屏幕、平显都是实时数据；
  --   座舱盖玻璃：Glass 材质（看出去有轻微折射）、内面一道道划痕和污渍、迎着日月光有眩光和划痕反光的放射纹；
  --   外面那套 2D 平显、外模型里的飞行员在座舱里时藏起来
  local function airEye(v, spec)
    local M = v.M
    local imp = M and M.imp
    local seat = (spec and spec.seat) or 1   -- 串列武装直升机：飞行员坐后座（2 号）；美军通用直升机机长坐右座（2 号）
    if imp and imp.info and imp.info.pit and imp.info.pit[seat] then
      local e = imp.info.pit[seat]
      return V(e[1], e[2], e[3]) + (imp.O or V())
    end
    local cf = M and (AM.seatCF(M, seat) or AM.seatCF(M, 1))
    if cf then
      local e = (cf * CF(0, 0.28, -0.25)).Position   -- 外模型飞行员的头：眼睛在头中心稍前
      -- 并排座的轰炸机：外模型只在中线摆了一个飞行员，机长坐左座，往左挪半个座舱
      if spec and spec.eyeShift and math.abs(e.X) < 0.3 then e += V(spec.eyeShift * S, 0, 0) end
      return e
    end
    return V(0, v.def.H * 0.35, -v.def.L * 0.3)
  end
  -- 玻璃上的划痕、污渍（内面；受光照，迎着光才看得清）
  scratches = function(part, seed)
    local rng = Random.new(seed)
    local sg = Instance.new("SurfaceGui")
    sg.Face = Enum.NormalId.Bottom
    sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    sg.PixelsPerStud = 120
    sg.LightInfluence = 1
    sg.Parent = part
    local W, H = part.Size.X * 120, part.Size.Z * 120
    local G2 = { part = part, sg = sg, list = {} }
    for _ = 1, 26 do
      local f = Instance.new("Frame")
      f.AnchorPoint = Vector2.new(0.5, 0.5)
      f.BorderSizePixel = 0
      f.BackgroundColor3 = RGB(255, 255, 255)
      f.BackgroundTransparency = 0.86 + rng:NextNumber() * 0.1
      f.Position = UDim2.fromOffset(rng:NextNumber() * W, rng:NextNumber() * H)
      f.Size = UDim2.fromOffset(8 + rng:NextNumber() * 60, 1)
      f.Rotation = rng:NextNumber() * 180
      f.Parent = sg
      -- 反光（用户 11-22：「一些小划痕有反光效果」）：每道划痕自己的方向——头一动，正好对上光的那几道一闪一闪
      table.insert(G2.list, { f = f, tr = f.BackgroundTransparency, ph = rng:NextNumber() * 6.283, k = 3 + rng:NextNumber() * 9 })
    end
    table.insert(glintList, G2)
    for _ = 1, 3 do   -- 污渍
      local f = Instance.new("Frame")
      f.AnchorPoint = Vector2.new(0.5, 0.5)
      f.BorderSizePixel = 0
      f.BackgroundColor3 = RGB(230, 230, 220)
      f.BackgroundTransparency = 0.95
      f.Position = UDim2.fromOffset(rng:NextNumber() * W, rng:NextNumber() * H)
      local r = 20 + rng:NextNumber() * 50
      f.Size = UDim2.fromOffset(r * 1.6, r)
      f.Parent = sg
      local cr = Instance.new("UICorner")
      cr.CornerRadius = UDim.new(0.5, 0)
      cr.Parent = f
    end
  end
  -- 光滑的座舱盖（InteriorDefs 给的 spec.canopy：沿机身一圈圈截面的 z、半径）：EditableMesh 拼成一整块光滑网格，
  --   法线按回转曲面算（看着是弧形、反光是一整片连续的高光，不是一条条棱），每个三角形正反各一份（从里面、外面都看得见）；
  --   玻璃材质的折射也跟着曲面走——从里面看出去外面的东西带一点点畸变（用户 11-22：「视角带点畸变」）。
  --   拼成了原来的平板就不画（带划痕的几块透明度 1，只留划痕）；拼不成（Studio 游戏设置 → 安全里没开 Mesh / Image API）：还用平板，反光调弱
  local meshWarned = false
  -- 拼不成光滑座舱盖时的平板（用户 11-24 晚：「目前飞机驾驶舱玻璃都是多边形 第一人称看非常难受」）：玻璃材质每块平板各折射、各反光，
  --   144 块的棱全看得见——改成几乎全透、不反光的塑料（看不出棱），只留带划痕那几块上的划痕、污渍（SurfaceGui，照样看得见）
  local function flatPanes(cp)
    for _, p in ipairs(cp.panes or {}) do
      p.Material = Enum.Material.SmoothPlastic
      p.Reflectance = 0
      p.Transparency = 0.975
    end
  end
  -- 摆好一块光滑座舱盖（导入的、现生成的都走这里）：玻璃材质、按机型的颜色透明度；off 是它在座舱（hull 组）里的位置
  local function useCanopy(c, cp, mp, off)
    mp.Name = "CanopySmooth"
    mp.Anchored, mp.CanCollide, mp.CanQuery, mp.CanTouch, mp.CastShadow = true, false, false, false, false
    mp.Material = Enum.Material.Glass
    mp.Color = cp.color or RGB(54, 62, 68)
    mp.Transparency = cp.trans or 0.88
    mp.Reflectance = cp.refl or 0.1
    local hw = c.b.groups.hull.world   -- 刚拼好座舱、还没摆过一帧时是空的：下一帧 pose 摆
    if hw then mp.CFrame = hw * off end
    mp.Parent = c.model
    table.insert(c.b.parts, { mp, c.b.groups.hull, off })
    c.plist[#c.b.parts] = mp
    for _, p in ipairs(cp.panes or {}) do p.Transparency = 1 end   -- 平板不画了（带划痕的几块只剩划痕）
    c.canopyMesh = mp
  end
  local function smoothCanopy(c)
    local cp = c.spec.canopy
    if not cp or c.canopyTried then return end
    c.canopyTried = true
    -- ① 导入的光滑座舱盖（models/optics/ip_canopy.glb，tools/weapons/gen_canopy.mjs 生成的同一个曲面）：不用 Mesh / Image API 也有
    if cp.std and G.opticParts and G.opticReady and G.opticReady("ip_canopy") then   -- 没导入、也没生成好：别让 Optics 再现生成一份（下面自己拼）
      local list = G.opticParts("ip_canopy")
      local it = list and list[1]
      if it and it.part then
        for i = 2, #list do list[i].part:Destroy() end
        useCanopy(c, cp, it.part, it.cf)   -- 器材坐标（格）就是座舱坐标 × 2.8；导入的 cf 里补回了转掉的半圈
        return
      end
    end
    task.spawn(function()
      local ok, mp, ctr = pcall(function()
        local AS = game:GetService("AssetService")
        local em = AS:CreateEditableMesh()
        local N, rows = cp.cols, cp.rows
        local P, Nn = {}, {}
        local lo, hi = V(1e9, 1e9, 1e9), V(-1e9, -1e9, -1e9)
        for j, row in ipairs(rows) do
          local a0, a1 = rows[math.max(1, j - 1)], rows[math.min(#rows, j + 1)]
          local dz = a1.z - a0.z
          local drdz = (math.abs(dz) > 1e-6) and (a1.r - a0.r) / dz or 0
          P[j], Nn[j] = {}, {}
          for i = 0, N do
            local a = math.rad(-90 + 180 * i / N)
            local p = V(math.sin(a) * row.r, cp.cy + math.cos(a) * row.r, row.z) * S
            P[j][i] = p
            Nn[j][i] = V(math.sin(a), math.cos(a), -drdz).Unit
            lo = V(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
            hi = V(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
          end
        end
        local center = (lo + hi) / 2
        local vid, nOut, nIn = {}, {}, {}
        for j = 1, #rows do
          vid[j], nOut[j], nIn[j] = {}, {}, {}
          for i = 0, N do
            vid[j][i] = em:AddVertex(P[j][i] - center)
            nOut[j][i] = em:AddNormal(Nn[j][i])
            nIn[j][i] = em:AddNormal(-Nn[j][i])
          end
        end
        local function tri(A, B, C)   -- A、B、C = { j, i }：外面一份（叉乘朝外）、里面一份（反着绕、法线朝里）
          local pa, pb, pc = P[A[1]][A[2]], P[B[1]][B[2]], P[C[1]][C[2]]
          local nrm = Nn[A[1]][A[2]] + Nn[B[1]][B[2]] + Nn[C[1]][C[2]]
          if (pb - pa):Cross(pc - pa):Dot(nrm) < 0 then B, C = C, B end
          local f1 = em:AddTriangle(vid[A[1]][A[2]], vid[B[1]][B[2]], vid[C[1]][C[2]])
          em:SetFaceNormals(f1, { nOut[A[1]][A[2]], nOut[B[1]][B[2]], nOut[C[1]][C[2]] })
          local f2 = em:AddTriangle(vid[A[1]][A[2]], vid[C[1]][C[2]], vid[B[1]][B[2]])
          em:SetFaceNormals(f2, { nIn[A[1]][A[2]], nIn[C[1]][C[2]], nIn[B[1]][B[2]] })
        end
        for j = 1, #rows - 1 do
          for i = 0, N - 1 do
            if (P[j][i] - P[j][i + 1]).Magnitude > 1e-4 then tri({ j, i }, { j, i + 1 }, { j + 1, i + 1 }) end
            if (P[j + 1][i] - P[j + 1][i + 1]).Magnitude > 1e-4 then tri({ j, i }, { j + 1, i + 1 }, { j + 1, i }) end
          end
        end
        local part = AS:CreateMeshPartAsync(Content.fromObject(em))
        return part, center
      end)
      if not ok or not mp then
        flatPanes(cp)
        if not meshWarned then
          meshWarned = true
          warn("[座舱] 光滑座舱盖生成不了（平板改成几乎全透；导入 models/optics/ip_canopy.glb，或者在 Studio 的游戏设置 → 安全里打开 Mesh / Image API）：" .. tostring(mp))
        end
        return
      end
      if cur ~= c or not c.model then mp:Destroy() return end
      useCanopy(c, cp, mp, CF(ctr))
    end)
  end
  -- 划痕反光：迎着日 / 月光（夜里还有照明弹）看过去，玻璃上的细划痕亮起来；每道按自己的方向闪（头一动一闪一闪）
  local function stepGlints(c)
    if #glintList == 0 then return end
    local ok, sun = pcall(function() return Lighting:GetSunDirection() end)
    local light, strong = nil, 1
    if ok and sun and sun.Y > -0.05 then light = sun end
    if not light then
      local ok2, moon = pcall(function() return Lighting:GetMoonDirection() end)
      if ok2 and moon and moon.Y > 0 then light, strong = moon, 0.55 end
    end
    local fl = G.brightFlare and G.brightFlare(cam.CFrame.Position)   -- 天上的照明弹（Warfx）：最亮的那颗
    local cp = cam.CFrame.Position
    local hy = look.yaw * 3.1 + look.pitch * 2.3
    for _, g2 in ipairs(glintList) do
      local p = g2.part
      if p.Parent then
        local v = (p.Position - cp)
        local vu = v.Magnitude > 1e-3 and v.Unit or cam.CFrame.LookVector
        local k = 0
        if light then k = math.max(0, (vu:Dot(light) - 0.45) / 0.55) * strong end
        if fl then k = math.max(k, math.max(0, (vu:Dot((fl - cp).Unit) - 0.55) / 0.45) * 0.8) end
        k = k * k
        g2.sg.LightInfluence = 1 - 0.8 * k
        g2.sg.Brightness = 1 + 2.5 * k
        for _, s3 in ipairs(g2.list) do
          local tw = 0.5 + 0.5 * math.sin(s3.ph + hy * s3.k)
          s3.f.BackgroundTransparency = s3.tr - (s3.tr - 0.25) * k * tw * tw
        end
      end
    end
  end
  -- 迎着日月光的眩光：光晕几圈 + 划痕反光的放射纹 + 玻璃整体发白一点
  local cfx = Instance.new("ScreenGui")
  cfx.Name = "CanopyFx"
  cfx.ResetOnSpawn = false
  cfx:SetAttribute("Fx", true)
  cfx.IgnoreGuiInset = true
  cfx.DisplayOrder = 4
  cfx.Enabled = false
  cfx.Parent = gui.Parent
  local haze = Instance.new("Frame")
  haze.Size = UDim2.fromScale(1, 1)
  haze.BackgroundColor3 = RGB(255, 250, 235)
  haze.BackgroundTransparency = 1
  haze.BorderSizePixel = 0
  haze.Parent = cfx
  local glows = {}
  for i = 1, 4 do
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.BackgroundColor3 = RGB(255, 248, 225)
    f.BorderSizePixel = 0
    f.Parent = cfx
    local cr = Instance.new("UICorner")
    cr.CornerRadius = UDim.new(0.5, 0)
    cr.Parent = f
    glows[i] = { f = f, r = 30 * i * i, t = 0.55 + i * 0.1 }
  end
  local streaks = {}
  for i = 1, 12 do
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.BackgroundColor3 = RGB(255, 252, 240)
    f.BorderSizePixel = 0
    f.Parent = cfx
    streaks[i] = { f = f, a = (i / 12) * 180 + (i % 3) * 7, l = 120 + (i % 4) * 70 }
  end
  local function stepGlare()
    local ok, sun = pcall(function() return Lighting:GetSunDirection() end)
    local light = (ok and sun and sun.Y > -0.05) and sun or nil
    local strong = 1
    if not light then
      local ok2, moon = pcall(function() return Lighting:GetMoonDirection() end)
      if ok2 and moon and moon.Y > 0 then light, strong = moon, 0.35 end
    end
    if not light then cfx.Enabled = false return end
    local lv = cam.CFrame.LookVector
    local k = lv:Dot(light)
    if k < 0.70 then cfx.Enabled = false return end
    local sp, onScreen = cam:WorldToViewportPoint(cam.CFrame.Position + light * 1000)
    if not onScreen then cfx.Enabled = false return end
    cfx.Enabled = true
    local a = math.clamp((k - 0.70) / 0.30, 0, 1) * strong
    for _, g in ipairs(glows) do
      g.f.Position = UDim2.fromOffset(sp.X, sp.Y)
      g.f.Size = UDim2.fromOffset(g.r * 2, g.r * 2)
      g.f.BackgroundTransparency = 1 - (1 - g.t) * a
    end
    for _, s2 in ipairs(streaks) do
      s2.f.Position = UDim2.fromOffset(sp.X, sp.Y)
      s2.f.Size = UDim2.fromOffset(s2.l * (0.6 + a), 1)
      s2.f.Rotation = s2.a
      s2.f.BackgroundTransparency = 1 - 0.32 * a
    end
    haze.BackgroundTransparency = 1 - 0.10 * a
  end
  -- 外面那套 2D 平显：在座舱里时不画（座舱里有真的平显）；顺手把这一帧的飞行数据留下来
  do
    local hud0 = G.airHudStep
    if hud0 then
      G.airHudStep = function(st, info)
        G.airInfo = info
        if mode and cur and cur.spec.air then return end
        return hud0(st, info)
      end
    end
    local tx0 = G.tankHudExtra   -- 飞机模式的 MWT 式界面（圆雷达、敌人名牌）：座舱里也不画，看座舱里的屏幕
    if tx0 then
      G.tankHudExtra = function(st, k, m)
        if m == "air" and mode and cur and cur.spec.air then return end
        return tx0(st, k, m)
      end
    end
  end
  local airContactsT, airContacts = 0, {}
  local function gatherAir(c, v, st)
    local d = c.data
    local body = v.cf
    local vel = st.vel or V()
    local sp = vel.Magnitude
    d.t = os.clock()
    d.clock = (Lighting.ClockTime or 0) * 3600
    d.kmh = sp / S * 3.6
    d.kt = d.kmh / 1.852
    d.altM = body.Position.Y / S
    d.agl = (body.Position.Y - math.max(G.Map.height(body.Position.X, body.Position.Z), 0)) / S
    d.vs = vel.Y / S
    local lk, rt, up = body.LookVector, body.RightVector, body.UpVector
    d.pitch = math.deg(math.asin(clamp(lk.Y, -1, 1)))
    d.roll = math.deg(math.atan2(-rt.Y, up.Y))
    d.hdg = math.deg(math.atan2(lk.X, -lk.Z)) % 360
    d.aoa = st.aoaDeg or 0
    local acc = st.accV or V()
    d.g = (acc:Dot(up) + 9.81 * S * up.Y) / (9.81 * S)
    d.mach = sp / S / 340
    d.thr = (st.d.kind == "heli") and (st.rpm or 0) or (st.thr or 0)   -- 直升机：发动机页按旋翼转速
    d.col = st.col
    d.fuel, d.fuelX = st.fuel or 1, st.fuelX or 0
    d.gear = st.gear or 0
    d.fwd = lk
    d.velDir = (sp > 5) and vel.Unit or lk
    d.pos = body.Position
    d.team = G.S and G.S.team
    d.ents = nearbyEnts(d.pos, st.id)
    d.points = {}
    if G.S and G.S.points then
      for _, p in ipairs(G.S.points) do
        for _, mp in ipairs(G.Map.POINTS) do
          if mp.id == p.id then table.insert(d.points, { id = p.id, x = mp.x, z = mp.z, owner = p.owner }) end
        end
      end
    end
    -- 挂载：每种剩几发（按挂点数加起来），选中的那种
    local wl = st.wl or {}
    local list = {}
    for i, wid in ipairs(wl) do
      local n = 0
      if st.d.gun == wid then n = st.gunAmmo or 0
      else
        for j, w2 in pairs(st.load or {}) do if w2 == wid then n += (st.stores and st.stores[j]) or 0 end end
      end
      local ok, nm = pcall(G.T, "aw." .. wid)
      table.insert(list, { name = ok and nm or wid, n = n, sel = i == st.wi })
    end
    d.weapons = list
    local selW = list[st.wi or 1]
    d.wpnText = selW and string.format("%s  ×%d", selW.name, selW.n) or ""
    d.lockDir = (st.lock and st.lock.pos) and (st.lock.pos - cam.CFrame.Position).Unit or nil
    d.lockAny = d.lockDir ~= nil
    -- 雷达：机头前 ±60°、80 公里里的飞机和车（半秒扫一次）
    if os.clock() - airContactsT > 0.5 then
      airContactsT = os.clock()
      airContacts = {}
      local folder = workspace:FindFirstChild("Ents")
      if folder then
        for _, em in ipairs(folder:GetChildren()) do
          local root = em:FindFirstChild("Root")
          if root and em:GetAttribute("EntId") ~= st.id and (em:GetAttribute("Hp") or 1) > 0 then
            local q = root.Position - body.Position
            local dist = q.Magnitude
            if dist < 80000 * 2.8 / 2.8 and dist > 30 then
              local az = math.deg(math.atan2(q:Dot(rt), q:Dot(lk)))
              if math.abs(az) < 60 then
                local kind = em:GetAttribute("Kind")
                if kind == "air" or kind == "veh" or kind == "ship" then
                  table.insert(airContacts, { az = az, km = dist / S / 1000, friend = em:GetAttribute("Team") == d.team, kind = kind,   -- kind：态势图分飞机 / 地面目标的符号
                    typ = entTyp(kind, em:GetAttribute("Cat"), em:GetAttribute("Model")),   -- 地面目标按兵种画军标（坦克、装甲车、防空……）
                    locked = st.lock and st.lock.id == em:GetAttribute("EntId") })
                end
              end
            end
          end
        end
      end
    end
    d.contacts = airContacts
    -- 告警
    local w = ""
    if d.agl < 150 and d.vs < -25 and (st.gear or 0) < 0.5 then w = c.spec.cn and "拉起" or "PULL UP"
    elseif st.d.stall and (st.spd or 99) < st.d.stall * 0.9 and not st.ground then w = c.spec.cn and "失速" or "STALL"
    elseif d.fuel + d.fuelX < 0.15 then w = c.spec.cn and "油量低" or "BINGO FUEL" end
    d.warn = w
    -- 平显的投影：世界方向 → 组合玻璃上的像素（按现在眼睛的位置算：看着像在无穷远）
    local hs = c.b.named.hud
    if hs then
      local hp = hs.part
      local P0, n = hp.Position, hp.CFrame.LookVector
      local C0 = cam.CFrame.Position
      local sz = hp.Size
      local W, Hh = hs.px.X, hs.px.Y
      d.hudProj = function(dir)
        local dn = dir:Dot(n)
        if math.abs(dn) < 1e-4 then return nil end
        local t = (P0 - C0):Dot(n) / dn
        if t <= 0 then return nil end
        local q = hp.CFrame:PointToObjectSpace(C0 + dir * t)
        return (0.5 - q.X / sz.X) * W, (0.5 - q.Y / sz.Y) * Hh
      end
    end
    return d
  end
  local function stepAirAnim(c, v, st, dt)
    local b = c.b
    local cc = st.c or {}
    local side = c.b.groups.stick and c.b.groups.stick.pivot.Position.X > 0.5
    local kp = side and 7 or 14
    c.sp = (c.sp or 0) + ((cc.pit or 0) - (c.sp or 0)) * math.min(1, dt * 12)
    c.sr = (c.sr or 0) + ((cc.rol or 0) - (c.sr or 0)) * math.min(1, dt * 12)
    local yw = cc.yaw or 0
    local colA = ANG(rad(((cc.col or 0) + 1) * 0.5 * 14 - 2), 0, 0)   -- 总距杆：提起来前端抬高（−1～1 → −2°～12°）
    for _, q in ipairs({ "", "2" }) do   -- 两座的操纵件联动（另一座带后缀 2）
      if c.spec.yoke then   -- 驾驶盘：驾驶柱前后推拉（俯仰）、盘绕柱转（滚转）
        b:setAnim("stick" .. q, ANG(rad(c.sp * 8), 0, 0))
        b:setAnim("wheel" .. q, ANG(0, 0, rad(-c.sr * 60)))
      else
        b:setAnim("stick" .. q, ANG(rad(c.sp * kp), 0, rad(-c.sr * kp)))
      end
      b:setAnim("coll" .. q, colA)
      b:setAnim("pedL" .. q, CF(0, 0, yw * 0.05))
      b:setAnim("pedR" .. q, CF(0, 0, -yw * 0.05))
    end
    b:setAnim("thr", CF(0, 0, -clamp((st.thr or 0) / 130, 0, 1) * 0.14))
    b:setAnim("thr2", CF(0, 0, -clamp((st.thr or 0) / 130, 0, 1) * 0.14))   -- 另一座那组（B-2）一起推；没有这组时不管
    b:setAnim("gearh", ANG(rad(((st.gear or 0) > 0.5) and 0 or -55), 0, 0))
    local now = os.clock()
    local hp = st.em and st.em:GetAttribute("Hp")
    local mh = st.em and st.em:GetAttribute("MaxHp")
    local hurt = hp and mh and mh > 0 and hp / mh < 0.4
    for _, l in ipairs(b.leds) do
      local on = true
      if l.role == "gear" then on = (st.gear or 0) > 0.9
      elseif l.role == "mwarn" then on = (hurt or c.data.warn == "PULL UP" or c.data.warn == "拉起") and math.floor(now * 3) % 2 == 0
      elseif l.role == "mcaut" then on = (c.data.warn ~= nil and c.data.warn ~= "") and math.floor(now * 2) % 2 == 0 end
      if c.lampT and now < c.lampT then on = true end
      l.p.Color = on and l.on or l.off
    end
    for _, L in ipairs(b.lights) do
      if L.role == "dome" then
        local kk = LIGHTK[lightMode]
        L.L.Enabled = kk > 0
        L.L.Brightness = L.bright * kk * 2
        L.L.Color = (lightMode == 3) and RGB(255, 80, 60) or ((lightMode == 2) and RGB(120, 230, 210) or L.color)
      elseif L.role == "warn" then
        local on = hurt and math.floor(now * 3) % 2 == 0
        L.L.Enabled = on
        L.L.Brightness = on and 1.2 or 0
      end
    end
  end
  -- 外模型在座舱里的部分（座舱盖玻璃、外模型自己的平显块、仪表板之类）：坐在座舱里时不画，免得和内饰叠在一起、玻璃隔两层
  local function zoneParts(c, v)
    local list = {}
    local M = v.M
    if not M or not M.items then return list end
    local e = c.eyeBody
    for _, it in ipairs(M.items) do
      local p = it.p
      -- 原模型自带的座舱（F-16，spec.modelPit）：座舱件（pit == "Pit"）就是内饰本身，不藏；原模型的平显（PitHud，玻璃上画死了符号）照旧藏
      if p and p:IsA("BasePart") and it.tag ~= "pilot" and not (c.spec.modelPit and it.pit == "Pit") then
        local cf = it.cf0 or (it.H and it.off and it.H * it.off)
        local glassy = p.Material == Enum.Material.Glass or (p.Transparency > 0.15 and p.Transparency < 1)
        local dist = cf and (cf.Position - e).Magnitude or math.huge
        local near = dist < 2.0 * S and p.Size.Magnitude < 3.2 * S
        -- 外模型自带的座舱（仪表板、座椅、平显、驾驶杆……原模型按材质并成的块，比 3.2 米大）挡在内饰的屏幕前面（用户 11-22：「飞机的电子屏会被挡住」）：
        --   包围球碰到眼睛周围那块座舱空间（左右 0.55、上 0.45、下 1.1、前 1.3、后 0.7 米）、又不是整架飞机那么大（最长不到 8 米）的也不画
        if not near and cf and math.max(p.Size.X, p.Size.Y, p.Size.Z) < 8 * S then
          local q = cf.Position - e
          local cx = math.clamp(q.X, -0.55 * S, 0.55 * S)
          local cy = math.clamp(q.Y, -1.1 * S, 0.45 * S)
          local cz = math.clamp(q.Z, -1.3 * S, 0.7 * S)
          local gap = (q - V(cx, cy, cz)).Magnitude
          if gap < p.Size.Magnitude / 2 then near = true end
        end
        -- 直升机的座舱窗是一整个大玻璃球（不是座舱盖件）：眼睛附近的玻璃都不画，看出去只隔内饰自己那层
        if (it.canopy and glassy) or near or (glassy and dist < 4.5 * S) then table.insert(list, p) end
      end
    end
    return list
  end
  local function zoneHide(c, on)
    for _, p in ipairs(c.zone or {}) do p.LocalTransparencyModifier = on and 1 or 0 end
    c.zoneOn = on
  end
  -- 线段 o→q 穿不穿过一个方块（cf、半边长 half）；o 在方块里面的不算（Roblox 只画朝外的面，从里面看不见）
  local function segHitsBox(o, q, cf, half)
    local lo, lq = cf:PointToObjectSpace(o), cf:PointToObjectSpace(q)
    if math.abs(lo.X) <= half.X and math.abs(lo.Y) <= half.Y and math.abs(lo.Z) <= half.Z then return false end
    local dv = lq - lo
    local t0, t1 = 0, 1
    for _, a in ipairs({ { lo.X, dv.X, half.X }, { lo.Y, dv.Y, half.Y }, { lo.Z, dv.Z, half.Z } }) do
      local x, dd, h = a[1], a[2], a[3]
      if math.abs(dd) < 1e-9 then
        if x < -h or x > h then return false end
      else
        local u, w = (-h - x) / dd, (h - x) / dd
        if u > w then u, w = w, u end
        if u > t0 then t0 = u end
        if w < t1 then t1 = w end
        if t0 > t1 then return false end
      end
    end
    return true
  end
  -- 挡在屏幕前面的外模型零件也不画（用户 11-22：「飞机的电子屏会被挡住」）：从这个座位的眼睛往每块屏幕（1.6 米以内）的中心和四个角打线，
  --   穿过的零件都收进 zone——轰-6 没导入模型时，座舱下面那段机身方块有 8.6 米长（上面按大小挑的规则不管），顶面正好盖住仪表板。
  --   都在机体坐标里算（外模型的 cf0 / H·off，内饰按这一帧的 v.cf 摆的），飞着进座舱也不差一帧；整架飞机那么大的件（最长超过机长、翼展的一半）不动
  local function occluders(c, v, eyeW)
    local M = v.M
    if not M or not M.items or not v.cf then return end
    local eB = v.cf:PointToObjectSpace(eyeW)
    local pts = {}
    for _, s in ipairs(c.b.screens) do
      if s.page ~= "hud" and s.part and s.part:IsA("BasePart") then
        local cf, hx, hy = s.part.CFrame, s.part.Size.X * 0.45, s.part.Size.Y * 0.45
        for _, k in ipairs({ { 0, 0 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
          local q = v.cf:PointToObjectSpace((cf * CF(k[1] * hx, k[2] * hy, 0)).Position)
          local len = (q - eB).Magnitude
          if len < 1.6 * S and len > 0.1 * S then table.insert(pts, eB + (q - eB) * (1 - 0.02 * S / len)) end
        end
      end
    end
    if #pts == 0 then return end
    local have = {}
    for _, p in ipairs(c.zone) do have[p] = true end
    local big = 0.5 * math.max(v.def.L or 0, v.def.W or 0)
    for _, it in ipairs(M.items) do
      local p = it.p
      if p and p:IsA("BasePart") and not have[p] and it.tag ~= "pilot" and not it.pit and p.Transparency < 0.5 and p.Material ~= Enum.Material.Glass then
        local cf = it.cf0 or (it.H and it.off and it.H * it.off)
        if cf and math.max(p.Size.X, p.Size.Y, p.Size.Z) < big then
          local half = p.Size / 2
          for _, q in ipairs(pts) do
            if segHitsBox(eB, q, cf, half) then
              have[p] = true
              table.insert(c.zone, p)
              if c.zoneOn then p.LocalTransparencyModifier = 1 end
              break
            end
          end
        end
      end
    end
  end
  stepAir = function(dt, st)
    local v = G.viewById and G.viewById(st.id)
    if not v or not v.cf or not v.def then return end
    if cur and cur.id ~= st.id then teardown() end
    if mode == nil or st.eo or st.bsight then   -- 车外 / 看光电吊舱 / 轰炸瞄准镜（Fly.lua 管镜头）：座舱收起来，外模型放回来
      if cur and cur.model.Parent then cur.model.Parent = nil end
      if cur and cur.pilotsHidden and v.M then pcall(AM.setPilots, v.M, true) cur.pilotsHidden = false end
      if cur and cur.zoneOn then zoneHide(cur, false) end
      hint.Visible, dot.Visible, tip.Visible = false, false, false
      cfx.Enabled = false
      hover, hoverScr = nil, nil
      return
    end
    if not cur then
      Kit.headMiss = nil
      cur = build(st, v)
      if not cur then mode = nil return end
      cur.headMiss = Kit.headMiss
      if not cur.b.propMiss and not cur.headMiss then cur.propsDone = true end
      cur.eyeBody = airEye(v, cur.spec)
      cur.zone = zoneParts(cur, v)
      if cur.spec.ihadss then   -- 阿帕奇的头盔单目显示（IHADSS）：符号画在眼前一块跟着头走的板上（视场 40°×30°，绿色）
        local p = Instance.new("Part")
        p.Name = "IHADSS"
        p.Size = V(0.364, 0.268, 0.002) * S
        p.Transparency = 1
        p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
        p.Parent = cur.model
        local sg = Kit.gui(p, Enum.NormalId.Front, 1400, 1.6)
        local root = Instance.new("Frame")
        root.Size = UDim2.fromScale(1, 1)
        root.BackgroundTransparency = 1
        root.Parent = sg
        local s2 = { part = p, gui = sg, root = root, w = 0.364, h = 0.268, page = "hud", opt = {}, px = V(0.364, 0.268, 0) * 1400 }
        s2.update = Screens.make(s2, cur.env)
        s2.nextT = 0
        table.insert(cur.b.screens, s2)
        cur.b.named.hud = s2
        cur.ihadss = s2
      end
      for i, g in ipairs(cur.spec.glass or {}) do scratches(g, i * 977 + #st.d.id) end
      smoothCanopy(cur)   -- 光滑座舱盖（拼成了平板就不画）
      enterStation(cur, station or lastStation[cur.key] or cur.spec.order[1])
      look.fovT, look.fov = 72, 72   -- 原来 85°：屏看着小、字看不清（用户 11-22：离电子屏不够近）
    end
    local c = cur
    if not c.model.Parent then c.model.Parent = workspace end
    G.interiorNow = c.model   -- 车内的零件：开车的测距 / 瞄准射线不算它（Drive.lua rayEx）
    if v.M and not c.pilotsHidden then pcall(AM.setPilots, v.M, false) c.pilotsHidden = true end
    if mode == "seat" then zoneHide(c, true) elseif c.zoneOn then zoneHide(c, false) end   -- 导演镜头从外面看：外模型完整
    frames(c, v)
    stepAirAnim(c, v, st, dt)
    frames(c, v)
    pose(c)
    -- 镜头：头跟着 Fly 的瞄准方向（有人开的固定翼 WASD 飞，瞄准方向就是航迹；无人机是鼠标给的方向）/ 镜头方向（直升机），限在脖子转得到的范围；大过载头往下沉、侧向过载歪
    local base, sp = stationCF(c, station)
    if base and mode == "seat" and c.occFor ~= station then   -- 换到这个座位后第一帧（内饰已经按这一帧摆好）：挡屏幕的外模型零件收起来
      c.occFor = station
      local ok, err = pcall(occluders, c, v, base.Position)
      if not ok then warn("[座舱] 挡屏幕的外模型：" .. tostring(err)) end
    end
    if base then
      if mode == "seat" then
        local aim
        if st.d.kind == "jet" then
          -- 按住 Alt 自由看（看下面的屏幕、按屏幕边的键）：鼠标只转头，准心不动（Fly.lua 这时不改准心）；松开头回到准心
          if UIS:IsKeyDown(Enum.KeyCode.LeftAlt) then
            local md = UIS:GetMouseDelta()
            local sens = 0.0035 * (look.fov / 72)
            c.fl = c.fl or { y = 0, p = 0 }
            c.fl.y -= md.X * sens
            c.fl.p = clamp(c.fl.p - md.Y * sens, -1.4, 1.4)
          else
            c.fl = nil
          end
          local fy, fp = c.fl and c.fl.y or 0, c.fl and c.fl.p or 0
          aim = (ANG(0, (st.aimYaw or 0) + fy, 0) * ANG(clamp((st.aimPitch or 0) + fp, -1.5, 1.5), 0, 0)).LookVector
          if st.flDir and not c.fl then aim = st.flDir end   -- 右键拖动的自由视角（Fly.lua）：头转向世界里那个方向，飞机怎么滚都盯着它
        else aim = (ANG(0, st.camYaw or 0, 0) * ANG(st.camPitch or 0, 0, 0)).LookVector end
        local l = base:VectorToObjectSpace(aim)
        local yw, pt = math.atan2(-l.X, -l.Z), math.asin(clamp(l.Y, -1, 1))
        -- 鼠标转头：右键拖动的自由视角（Fly.lua 的 st.flDir，世界方向）已经在 aim 里
        yw = clamp(yw, -rad(sp.yaw or 150), rad(sp.yaw or 150))
        pt = clamp(pt, -rad(sp.down or 60), rad(sp.up or 80))
        look.yaw += (yw - look.yaw) * math.min(1, dt * 9)
        look.pitch += (pt - look.pitch) * math.min(1, dt * 9)
        local acc = st.accV and base:VectorToObjectSpace(st.accV) / (9.81 * S) or V()
        c.headOff = (c.headOff or V()):Lerp(V(clamp(-acc.X * 0.012, -0.04, 0.04), clamp(-acc.Y * 0.008, -0.06, 0.03), 0), math.min(1, dt * 6))
        look.fov += (look.fovT - look.fov) * math.min(1, dt * 10)
        cam.CFrame = base * CF(c.headOff * S) * ANG(0, look.yaw, 0) * ANG(look.pitch, 0, 0)
        cam.FieldOfView = look.fov
      else
        setCamera(c, dt)
      end
    end
    stepCrew(c, cam.CFrame.LookVector)
    if c.ihadss then   -- 头盔显示跟着头：眼前半米；导演镜头、换到前座时不画
      local on = mode == "seat" and station == c.spec.order[1]
      c.ihadss.gui.Enabled = on
      c.ihadss.part.CFrame = cam.CFrame * CF(0, 0, -0.5 * S) * ANG(0, math.pi, 0)
    end
    -- 屏幕
    local now = os.clock()
    local d = nil
    for _, s2 in ipairs(c.b.screens) do
      if s2.update and now >= (s2.nextT or 0) then
        local fast = s2.page == "hud"
        s2.nextT = now + (fast and 0 or 0.1)
        d = d or gatherAir(c, v, st)
        local ok, err = pcall(s2.update, d)
        if not ok then
          s2.update = nil
          warn("[座舱] 屏幕 " .. tostring(s2.page) .. "：" .. tostring(err))
        end
      end
    end
    stepKeys(c)
    stepGlare()
    stepGlints(c)
    hint.Visible = not hideUI
    hint.Text = T("V 出座舱 · 鼠标转头看（停 2.5 秒回正、C 立刻回正）· 滚轮变焦 · 中间小点对准屏幕边的按键左键按 · K 导演镜头 · L 座舱灯 · U 藏界面",
      "V exit cockpit · mouse turns your head (recenters after 2.5 s, C at once) · wheel zoom · dot on a bezel key + click · K free cam · L lights · U hide UI")
  end

  ---------------------------------------------------------------- 按键

  local KEYST = { [Enum.KeyCode.F2] = "driver", [Enum.KeyCode.F3] = "gunner", [Enum.KeyCode.F4] = "commander", [Enum.KeyCode.F5] = "loader" }
  UIS.InputBegan:Connect(function(io, gp)
    if gp then return end
    local fst = G.fly
    if fst and fst.d and fst.pilot and not fst.uav and not fst.eo and not fst.bsight and Defs[fst.d.id] and fpAllowed(fst.d.id) then   -- 飞机：V 进出座舱、F2 / F3 前后座、B / L / U 同坦克
      local k = io.KeyCode
      if io.UserInputType == Enum.UserInputType.MouseButton1 and hover and mode == "seat" and cur then
        if hover.mov then movPress(cur, hover.mov) return end
        local s2 = hover.screen
        if s2 and s2.onKey then pcall(s2.onKey, hover.label, cur.env.act) s2.nextT = 0 end
        hover.part.Color = RGB(255, 255, 255)
        return
      end
      if k == Enum.KeyCode.V then
        if mode then
          mode = nil
          cam.FieldOfView = 70
        else
          mode = "seat"
          if cur then enterStation(cur, lastStation[cur.key] or cur.spec.order[1]) end
        end
      elseif (k == Enum.KeyCode.F2 or k == Enum.KeyCode.F3) and cur and mode then   -- 前后座 / 左右座 / 射手座
        local want = cur.spec.order[(k == Enum.KeyCode.F2) and 1 or 2]
        if want and cur.spec.stations[want] then enterStation(cur, want) end
      elseif k == Enum.KeyCode.K and cur and mode then   -- 导演镜头（飞机上 B 是减速板 / 刹车，换成 K）
        if mode == "free" then enterStation(cur, station or "pilot")
        else
          mode = "free"
          local g = cur.b.groups.hull.world
          local rel = g:ToObjectSpace(cam.CFrame)
          free.p = rel.Position
          local lv = rel.LookVector
          free.yaw, free.pitch = math.atan2(-lv.X, -lv.Z), math.asin(clamp(lv.Y, -1, 1))
        end
      elseif k == Enum.KeyCode.L and cur and mode and not (G.mslFollowAvail and G.mslFollowAvail()) then lightMode = lightMode % #LIGHTS + 1   -- 有自己的导弹在飞：L 让给跟踪导弹（MslCam.lua）
      elseif k == Enum.KeyCode.U and (mode or hideUI) then setHideUI(not hideUI) end
      return
    end
    local st = G.drive
    if not st or not st.d or G.myVeh ~= st then return end
    if io.UserInputType == Enum.UserInputType.MouseButton1 and hover and hover.mov and mode == "seat" and cur then   -- 拨对准的那个旋钮 / 开关 / 按钮
      movPress(cur, hover.mov)
      return
    end
    if io.UserInputType == Enum.UserInputType.MouseButton1 and hover and mode == "seat" and cur then   -- 按下对准的那个键
      local s2 = hover.screen
      if s2 and s2.onKey then
        local ok, err = pcall(s2.onKey, hover.label, cur.env.act)
        if not ok then warn("[内饰] 按键 " .. tostring(hover.label) .. "：" .. tostring(err)) end
        s2.nextT = 0
      end
      hover.part.Color = RGB(255, 255, 255)
      if G.sfx then pcall(G.sfx, "dry") end
      return
    end
    local k = io.KeyCode
    if k == Enum.KeyCode.T and (mode == nil or (optic and optic.quick)) and not st.sight then
      -- T：车外直接进车长的主观瞄（用户 11-21：99A 模型上那个多边形的观瞄舱——车长周视瞄准镜，要能第一人称看出去；M1A2 是 CITV）：
      --   坐到车长位、开他的主镜（镜头在观瞄舱的位置，鼠标转镜头、炮塔不动，Z 变倍、V 换热像）；这样开的镜里再按 T：关镜、回车外
      if optic and optic.quick then
        exitOptic(cur)
        mode = nil
        if cur and cur.model.Parent then cur.model.Parent = nil end
        cam.FieldOfView = 70
      else
        mode, station, quickOptic = "seat", "commander", true
      end
    elseif k == Enum.KeyCode.C then
      if mode == nil then
        -- 11-27：车外的 C 归车长望远镜（Drive.lua / GunSight.lua，用户「再做一个望远镜」）——进车内用 F2～F5（直接坐到那个乘员位）或 T（车长主观瞄）；
        --   车里面 C 照旧是换下一个乘员位、最后回车外
        return
      elseif mode == "seat" and cur then
        -- 依次换到下一个乘员位，最后一个之后回车外
        local order = cur.spec.order
        local idx = 0
        for i, s in ipairs(order) do if s == station then idx = i end end
        if idx >= #order and workspace:GetAttribute("WtMode") == "sb" and not (G.inTestDrive and G.inTestDrive()) then   -- 全真模式（战雷）：只能第一人称，转一圈回第一个乘员位，不回车外（试驾不管）
          enterStation(cur, order[1])
        elseif idx >= #order then
          mode = nil
          if cur.model.Parent then cur.model.Parent = nil end
          cam.FieldOfView = 70
        else
          enterStation(cur, order[idx + 1])
        end
      else
        mode = nil
      end
    elseif KEYST[k] then
      local want = KEYST[k]
      if cur and not (cur.spec.lock and cur.spec.stations[want]) then   -- 坦克有这个名字的乘员位就去它（F2 驾驶员、F3 炮长、F4 车长、F5 装填手）；别的车按这型车的乘员位顺序
        local idx = ({ [Enum.KeyCode.F2] = 1, [Enum.KeyCode.F3] = 2, [Enum.KeyCode.F4] = 3, [Enum.KeyCode.F5] = 4 })[k]
        want = cur.spec.order[idx] or want
      end
      if not cur then
        mode = "seat"
        station = want
      elseif cur.spec.stations[want] then
        enterStation(cur, want)
      end
    elseif k == Enum.KeyCode.B and cur and mode then
      if mode == "free" then
        enterStation(cur, station or cur.spec.order[1])
      else
        mode = "free"
        local base, sp = stationCF(cur, station or cur.spec.order[1])
        local g = cur.b.groups.hull.world
        if base then
          local rel = g:ToObjectSpace(base * ANG(0, look.yaw, 0) * ANG(look.pitch, 0, 0))
          free.p = rel.Position
          local lv = rel.LookVector
          free.yaw = math.atan2(-lv.X, -lv.Z)
          free.pitch = math.asin(clamp(lv.Y, -1, 1))
        end
        local _ = sp
      end
    elseif (k == Enum.KeyCode.G or k == Enum.KeyCode.T) and cur and mode == "seat" then   -- 备用镜 / 第三个观瞄设备
      local slot = (k == Enum.KeyCode.G) and "alt" or "third"
      if optic then
        local same = optic.slot == slot
        exitOptic(cur)
        if same then return end
      end
      if st.sight and G.driveSetSight then G.driveSetSight(false) return end
      enterOptic(cur, slot)
    elseif k == Enum.KeyCode.L and cur and mode and not (G.mslFollowAvail and G.mslFollowAvail()) then
      lightMode = lightMode % #LIGHTS + 1
    elseif k == Enum.KeyCode.U and (mode or hideUI) then
      setHideUI(not hideUI)
    end
  end)
  UIS.InputChanged:Connect(function(io, gp)
    if gp or not mode or not cur then return end
    if io.UserInputType == Enum.UserInputType.MouseWheel then
      if optic then   -- 观瞄设备：换视场
        local n = #optic.o.fovs
        optic.zi = math.clamp(optic.zi + ((io.Position.Z > 0) and 1 or -1), 1, n)
        return
      end
      local st = G.drive
      if st and st.sight then return end
      look.fovT = clamp(look.fovT - io.Position.Z * 6, 25, 100)
    end
  end)
end

return Interior
