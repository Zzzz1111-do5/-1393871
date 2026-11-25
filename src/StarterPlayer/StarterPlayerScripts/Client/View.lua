-- Roblox全面大战场（客户端）——实体的样子：服务器上只有一个隐形的 Root（位置）和属性（Kind 种类、Team 队伍、Hp 血量……），
--   这里按种类拼一个本地模型，每帧平滑地跟着 Root 走（服务器 10～15 次 / 秒地挪，直接跟会一顿一顿的）；头顶血条
--   机器人步兵（摆腿走路、倒地）、登陆艇（放跳板、被打沉往下沉）、气垫艇、炸药包、地雷
--   地面载具（VehModels 拼的）：每个车轮 / 负重轮各自一个弹簧阻尼（按脚下的地面高度 + 细碎的颠簸，过坡上下抖），
--     车体跟着轮子上下、前后俯仰、左右侧倾（也带弹簧，刹车点头、起步抬头）；炮塔、炮按属性 Ty / Gp 转（自己开的车用本地的），
--     开炮后坐、车轮按走的路转、前轮转向、雷达转、扬尘、被毁冒火冒黑烟；零件一次 BulkMoveTo
--   别的模块能登记自己的样子：G.viewKind[种类] = { build(v, em, team), step(v, dt, camPos), recoil(v), remove(v) }（工事在 FortView）
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local View = {}

function View.init(G)
  local Config = G.Config
  local Map = require(RS:WaitForChild("Map"))
  local Debris = game:GetService("Debris")
  local VD = require(RS:WaitForChild("VehDefs"))
  local VM = require(script.Parent:WaitForChild("VehModels"))
  local TT = require(RS:WaitForChild("TechTree"))   -- 科技树暂用车的真车涂装（TreeKey 属性）
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer

  -- 一个 Model 装所有实体的样子：热成像时整个打一个高亮（Highlight 有数量上限）
  local VF = Instance.new("Model")
  VF.Name = "EntView"
  VF.Parent = workspace
  G.viewFolder = VF

  local function p(m, size, cf, color, mat, shape)
    local x = Instance.new("Part")
    if shape then x.Shape = shape end
    x.Size, x.CFrame, x.Color = size, cf, color
    x.Material = mat or Enum.Material.SmoothPlastic
    x.Anchored, x.CanCollide, x.CanQuery, x.CanTouch = true, false, false, false
    x.TopSurface, x.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    x.Parent = m
    return x
  end

  -- 每种实体：拼零件（相对 Root 的偏移记在 parts 里），每帧额外动（腿、跳板）
  local UNIFORM = { atk = { RGB(150, 128, 92), RGB(110, 96, 70) }, def = { RGB(84, 104, 70), RGB(64, 78, 54) } }
  local KINDS = {}
  -- 机器人：服务器的命中盒高 5.6 格、中心在脚底上 2.8 格
  KINDS.bot = function(m, team)
    local U = UNIFORM[team] or UNIFORM.atk
    local L = {}
    L.torso = { p(m, V(2, 2, 1), CF(), U[1]), CF(0, 0.4, 0) }
    L.vest = { p(m, V(2.15, 1.3, 1.25), CF(), U[2]), CF(0, 0.55, 0) }
    L.head = { p(m, V(1.2, 1.2, 1.2), CF(), RGB(230, 190, 150)), CF(0, 2.0, 0) }
    L.helmet = { p(m, V(1.45, 0.65, 1.45), CF(), U[2], Enum.Material.SmoothPlastic), CF(0, 2.55, 0) }
    -- 夜视仪：头盔前面的支架和双筒（机器人夜里一直戴着、翻下来）
    L.nvg = { p(m, V(0.62, 0.24, 0.3), CF(), RGB(28, 30, 32), Enum.Material.Metal), CF(0, 2.22, -0.78) }
    for sx = -1, 1, 2 do
      L["nvgTube" .. sx] = { p(m, V(0.42, 0.24, 0.24), CF(), RGB(22, 24, 26), Enum.Material.Metal, Enum.PartType.Cylinder),
        CF(sx * 0.17, 2.12, -1.0) * CFrame.Angles(0, math.pi / 2, 0) }
    end
    L.lleg = { p(m, V(0.9, 2, 0.9), CF(), U[2]), CF(-0.5, -1.6, 0), "leg", 1 }
    L.rleg = { p(m, V(0.9, 2, 0.9), CF(), U[2]), CF(0.5, -1.6, 0), "leg", -1 }
    L.larm = { p(m, V(0.8, 1.9, 0.8), CF(), U[1]), CF(-1.2, 0.5, -0.5) * CFrame.Angles(-1.2, 0.35, 0) }
    L.rarm = { p(m, V(0.8, 1.9, 0.8), CF(), U[1]), CF(1.3, 0.5, -0.4) * CFrame.Angles(-1.2, 0, 0) }
    L.gun = { p(m, V(0.35, 0.45, 3.2), CF(), RGB(45, 47, 50), Enum.Material.Metal), CF(0.35, 0.75, -1.7) }
    L.band = { p(m, V(0.85, 0.35, 0.85), CF(), Config.Teams[team or "atk"].color, Enum.Material.Neon), CF(1.3, 1.0, -0.3) }
    return L
  end
  KINDS.lcm = function(m, team)
    local L = {}
    local hull = RGB(96, 104, 98)
    L.bottom = { p(m, V(16, 2, 34), CF(), hull, Enum.Material.Metal), CF(0, -2, 0) }
    L.lwall = { p(m, V(1, 6, 34), CF(), hull, Enum.Material.Metal), CF(-7.5, 1, 0) }
    L.rwall = { p(m, V(1, 6, 34), CF(), hull, Enum.Material.Metal), CF(7.5, 1, 0) }
    L.back = { p(m, V(16, 7, 1), CF(), hull, Enum.Material.Metal), CF(0, 1.5, 16.5) }
    L.cab = { p(m, V(6, 4, 4), CF(), RGB(120, 128, 120), Enum.Material.Metal), CF(0, 5, 14) }
    L.ramp = { p(m, V(15, 6, 0.8), CF(), hull, Enum.Material.Metal), CF(0, 1, -17), "ramp" }
    return L
  end
  -- 726 型气垫艇：黑色气垫围裙、甲板、两侧上层建筑、尾部两个大风扇
  KINDS.lcac = function(m)
    local L = {}
    local grey = RGB(112, 120, 116)
    L.skirt = { p(m, V(28, 3, 48), CF(), RGB(30, 30, 32), Enum.Material.Fabric), CF(0, -1.6, 0) }
    L.deck = { p(m, V(24, 1, 44), CF(), grey, Enum.Material.DiamondPlate), CF(0, 0.2, 0) }
    for s = -1, 1, 2 do
      L["side" .. s] = { p(m, V(3, 4, 40), CF(), grey, Enum.Material.Metal), CF(s * 12.5, 2.3, 0) }
      L["fan" .. s] = { p(m, V(2, 9, 9), CF(), RGB(70, 74, 72), Enum.Material.Metal, Enum.PartType.Cylinder), CF(s * 6, 6, 20) * CFrame.Angles(0, math.pi / 2, 0) }
      L["fin" .. s] = { p(m, V(0.4, 6, 3), CF(), grey, Enum.Material.Metal), CF(s * 6, 6, 23.5) }
    end
    L.bridge = { p(m, V(4, 4, 6), CF(), grey, Enum.Material.Metal), CF(10.5, 6.2, -14) }
    return L
  end
  KINDS.c4 = function(m) return { b = { p(m, V(1.1, 0.5, 0.7), CF(), RGB(176, 156, 112)), CF() }, l = { p(m, V(0.2, 0.2, 0.2), CF(), RGB(255, 40, 40), Enum.Material.Neon), CF(0, 0.3, 0) } } end
  KINDS.mine = function(m) return { b = { p(m, V(0.4, 1.4, 1.4), CF(), RGB(86, 96, 64), Enum.Material.Metal, Enum.PartType.Cylinder), CFrame.Angles(0, 0, math.pi / 2) } } end

  local views = {}   -- [entModel] = { model, parts, cf, kind, t, … }
  G.views = views
  local byId = {}    -- [实体编号] = view（开炮后坐要按编号找）
  G.viewById = function(id) return byId[id] end
  local function bar(m, adornee, h)
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(46, 6)
    bb.StudsOffsetWorldSpace = V(0, h or 5, 0)
    bb.MaxDistance = 260
    bb.Adornee = adornee
    bb.Parent = m
    local bg = Instance.new("Frame")
    bg.Size = UDim2.fromScale(1, 1)
    bg.BackgroundColor3 = RGB(0, 0, 0)
    bg.BackgroundTransparency = 0.4
    bg.BorderSizePixel = 0
    bg.Parent = bb
    local f = Instance.new("Frame")
    f.Size = UDim2.fromScale(1, 1)
    f.BorderSizePixel = 0
    f.Parent = bg
    return bb, f
  end

  local function add(em)
    if views[em] then return end
    local kind = em:GetAttribute("Kind")
    local root = em:FindFirstChild("Root")
    if not root then return end
    local team = em:GetAttribute("Team")
    local v = { cf = root.CFrame, root = root, kind = kind, t = 0, team = team, id = em:GetAttribute("EntId"), em = em }
    local ext = G.viewKind and G.viewKind[kind]   -- 别的模块登记的样子（工事 FortView……）：build 设好 v.model、v.anchor（血条挂点）
    if kind == "veh" then
      local d = VD.get(em:GetAttribute("Model") or "")
      if not d then return end
      -- 科技树出的车（TreeKey）：还没有原模型、用零件拼的按真车涂装上色（TechTree.paint；用户 11-25「很多车涂装纯米黄」），不按阵营刷沙色
      local tk = em:GetAttribute("TreeKey")
      local tit = (type(tk) == "string") and TT.get(tk) or nil
      local M = VM.build(d, team, em:GetAttribute("Mods"), tit and TT.paint(tit) or nil)   -- 坦克改装：发射器、雷达板、加特林、补贴的爆反块（TankMods）
      M.model.Parent = VF
      v.modsAttr = em:GetAttribute("Mods")
      v.treeKey = tk
      v.M, v.def, v.model = M, d, M.model
      v.ty, v.gp, v.recoil = em:GetAttribute("Ty") or 0, em:GetAttribute("Gp") or 0, 0
      v.bob, v.bobV, v.pitch, v.pitchV, v.roll, v.rollV = 0, 0, 0, 0, 0, 0
      v.speed, v.steer, v.lastPos, v.lastYaw = 0, 0, root.CFrame.Position, 0
      v.plist, v.clist = {}, {}
      for i, it in ipairs(M.parts) do v.plist[i] = it[1] end
      local anchor = Instance.new("Part")   -- 血条挂的点（在车顶上）
      anchor.Size, anchor.Transparency, anchor.Anchored = V(0.2, 0.2, 0.2), 1, true
      anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = false, false, false
      anchor.Parent = M.model
      v.anchor = anchor
      v.bb, v.fill = bar(M.model, anchor, 2)
      v.bb.MaxDistance = 600
    elseif ext then
      if not ext.build(v, em, team) or not v.model then return end
      v.ext = ext
      v.model.Parent = VF
      v.bb, v.fill = bar(v.model, v.anchor, 2)
      v.bb.MaxDistance = 600
    else
      local mk = KINDS[kind]
      if not mk then return end
      local m = Instance.new("Model")
      m.Name = kind
      v.parts = mk(m, team)
      v.model = m
      m.Parent = VF
      v.bb, v.fill = bar(m, v.parts[next(v.parts)][1])
    end
    v.fill.BackgroundColor3 = Config.Teams[team or "atk"].color
    views[em] = v
    if v.id then byId[v.id] = v end
  end

  -- 实体没了：被打死的步兵倒地几秒、被打沉的艇往下沉，其余直接删
  local dying = {}
  local function engSndOff(v)   -- 别人的车的发动机、履带声（stepVeh 里挂的）
    if v.engS then
      for _, s in pairs(v.engS) do s:Destroy() end
      v.engS = nil
    end
  end
  local function remove(em)
    local v = views[em]
    if not v then return end
    views[em] = nil
    if v.id then byId[v.id] = nil end
    engSndOff(v)
    local hp = em:GetAttribute("Hp") or 1
    if v.ext and v.ext.remove then
      local ok, keep = pcall(v.ext.remove, v)
      if not ok and G.showError then G.showError("local view: " .. tostring(keep)) end
      if ok and keep == true then return end   -- 自己收尾（机器人倒地，Soldier.lua）
    end
    if hp <= 0 and v.kind ~= "veh" and not v.ext then
      v.t0 = os.clock()
      if v.bb then v.bb:Destroy() end
      table.insert(dying, v)
    else
      v.model:Destroy()
    end
  end
  local function stepDying()
    local t = os.clock()
    for i = #dying, 1, -1 do
      local v = dying[i]
      local a = t - v.t0
      if a > ((v.kind == "bot") and 6 or 5) then
        v.model:Destroy()
        table.remove(dying, i)
      else
        local cf
        if v.kind == "bot" then   -- 绕脚底往后倒
          local k = math.clamp(a / 0.45, 0, 1)
          cf = v.cf * CF(0, -2.8, 0) * CFrame.Angles(k * k * 1.45, 0, 0) * CF(0, 2.8 - 0.4 * k, 0)
        else
          cf = v.cf * CF(0, -a * 2.2, 0) * CFrame.Angles(0, 0, a * 0.12)
        end
        for _, L in pairs(v.parts) do L[1].CFrame = cf * L[2] end
      end
    end
  end

  -- 开炮：这辆车的炮往后坐一下；坦克、自行火炮的车体还被后坐力推得一晃（炮朝前开就抬头、朝侧面开就往另一边歪，弹簧摆两下才停——战雷那样）
  -- 炮的后坐曲线（用户 11-22：「坦克开炮，第一人称的时候那个炮管会瞬间往后」——原来开炮那一帧整段后坐一下子到位，再直线滑回去）：
  --   大炮 0.08 秒往后坐到底（先快后慢），顶住一下，到 0.62 秒复进完（两头慢中间快）；机关炮短：0.02 秒坐到底、0.14 秒回来。返回 0～1
  local function recoilCurve(t, big)
    if not t or t < 0 then return 0 end
    local a, h, e = 0.08, 0.11, 0.62
    if not big then a, h, e = 0.02, 0.025, 0.14 end
    if t < a then local u = t / a return 1 - (1 - u) * (1 - u) end
    if t < h then return 1 end
    if t < e then local u = (t - h) / (e - h) return 1 - u * u * (3 - 2 * u) end
    return 0
  end
  G.recoilCurve = recoilCurve
  function G.vehRecoil(id, g)   -- g：第几门炮（舰艇有前后两门的）
    local v = byId[id]
    if v and v.kind == "veh" then
      local big = v.def.cat == "tank" or v.def.cat == "arty"
      v.recoilA, v.recoilT, v.recoilBig = big and 1.7 or 0.35, 0, big
      v.shots = (v.shots or 0) + 1   -- 开了第几炮（Interior 按这个数接着放炮闩、装填手的动作）
      v.recoil = v.recoilA * recoilCurve(0.25 / 60, big)
      if big and not v.wrecked then
        local a = math.rad(v.ty or 0)
        local k = (v.def.cat == "arty") and 0.95 or 0.8
        v.pitchV = (v.pitchV or 0) + k * math.cos(a)
        v.rollV = (v.rollV or 0) + k * math.sin(a)
        v.bobV = (v.bobV or 0) - 2.5
      end
    elseif v and v.ext and v.ext.recoil then v.ext.recoil(v, g) end
  end

  ---------------------------------------------------------------- 弹药殉爆：炮塔连炮整个掀飞（用户：坦克被打爆盖子可以飞起来，动画逼真一点）
  -- 被毁的那一下，座圈里先喷一柱火，炮塔带着炮转着往上飞一两层楼高，落地砸起土、迸火星，弹一两下歪着停住；车体接着烧、殉爆的小炸响几声。
  -- 随机数按车的编号定：每个人看到的是同一个样子
  local TOSS_G = 9.81 * 2.8 * 1.25   -- 重力（格/秒²，略重一点，落得干脆）
  local trackMark   -- 履带印（下面定义）
  local function tossFx(p, big)
    if not G.fxPart then return end
    local part = G.fxPart
    -- 一柱火：从座圈直冲上去
    local h = part(nil, V(0.4, 0.4, 0.4), CFrame.lookAt(p, p + V(0, 1, 0)), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
    local fire = Instance.new("ParticleEmitter")
    fire.Texture = "rbxasset://textures/particles/fire_main.dds"
    fire.Rate = 0
    fire.Lifetime = NumberRange.new(0.35, 0.8)
    fire.Speed = NumberRange.new(28, 60)
    fire.SpreadAngle = Vector2.new(14, 14)
    fire.Drag = 1.5
    fire.LightEmission = 1
    fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3.5), NumberSequenceKeypoint.new(0.5, 7), NumberSequenceKeypoint.new(1, 2) })
    fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
    fire.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, RGB(255, 246, 200)), ColorSequenceKeypoint.new(0.4, RGB(255, 160, 60)), ColorSequenceKeypoint.new(1, RGB(120, 40, 20)) })
    fire.EmissionDirection = Enum.NormalId.Front
    fire.Parent = h
    fire:Emit(big and 70 or 40)
    -- 火星：往四周上方撒，带重力落下来
    local sp = Instance.new("ParticleEmitter")
    sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    sp.Rate = 0
    sp.Lifetime = NumberRange.new(0.8, 1.8)
    sp.Speed = NumberRange.new(30, 70)
    sp.SpreadAngle = Vector2.new(60, 60)
    sp.Acceleration = V(0, -60, 0)
    sp.LightEmission = 1
    sp.Size = NumberSequence.new(0.35)
    sp.Color = ColorSequence.new(RGB(255, 210, 120))
    sp.EmissionDirection = Enum.NormalId.Front
    sp.Parent = h
    sp:Emit(big and 90 or 50)
    -- 黑烟蘑菇云
    local sm = Instance.new("ParticleEmitter")
    sm.Texture = "rbxasset://textures/particles/smoke_main.dds"
    sm.Rate = 0
    sm.Lifetime = NumberRange.new(2.5, 4.5)
    sm.Speed = NumberRange.new(14, 30)
    sm.SpreadAngle = Vector2.new(30, 30)
    sm.Drag = 1.2
    sm.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 20) })
    sm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
    sm.Color = ColorSequence.new(RGB(34, 30, 28))
    sm.EmissionDirection = Enum.NormalId.Front
    sm.Parent = h
    sm:Emit(big and 26 or 14)
    Debris:AddItem(h, 6)
    if G.flash then G.flash(p + V(0, 6, 0), RGB(255, 170, 80), 70, 14, 0.9) end
    if G.playSound then
      G.playSound("boom", p, 0.5)
      for i = 1, 4 do   -- 车里的炮弹接着一发发殉爆：闷闷的几声
        task.delay(0.5 + i * 0.45 + math.random() * 0.3, function()
          G.playSound("mortar", p, 0.7 + math.random() * 0.3)
          if G.flash then G.flash(p + V(0, 2, 0), RGB(255, 150, 70), 30, 5, 0.25) end
        end)
      end
    end
    if G.shake then
      local cam = workspace.CurrentCamera
      local dd = cam and (cam.CFrame.Position - p).Magnitude or 999
      if dd < 220 then G.shake(0.5 * (1 - dd / 220)) end
    end
  end
  local function landFx(p)
    if not G.fxPart then return end
    local part, tween = G.fxPart, G.tween
    local ring = part(Enum.PartType.Cylinder, V(0.5, 6, 6), CFrame.new(p) * CFrame.Angles(0, 0, math.pi / 2), RGB(120, 106, 84), Enum.Material.SmoothPlastic, 0.35)
    tween(ring, 0.6, { Size = V(0.5, 26, 26), Transparency = 1 })
    Debris:AddItem(ring, 0.65)
    local h = part(nil, V(0.4, 0.4, 0.4), CFrame.lookAt(p, p + V(0, 1, 0)), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
    local du = Instance.new("ParticleEmitter")
    du.Texture = "rbxasset://textures/particles/smoke_main.dds"
    du.Rate = 0
    du.Lifetime = NumberRange.new(1, 2.2)
    du.Speed = NumberRange.new(8, 22)
    du.SpreadAngle = Vector2.new(75, 75)
    du.Drag = 2.5
    du.Acceleration = V(0, -4, 0)
    du.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 11) })
    du.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
    du.Color = ColorSequence.new(RGB(140, 124, 98))
    du.EmissionDirection = Enum.NormalId.Front
    du.Parent = h
    du:Emit(22)
    local sp = Instance.new("ParticleEmitter")
    sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    sp.Rate = 0
    sp.Lifetime = NumberRange.new(0.3, 0.7)
    sp.Speed = NumberRange.new(20, 40)
    sp.SpreadAngle = Vector2.new(80, 80)
    sp.Acceleration = V(0, -70, 0)
    sp.LightEmission = 1
    sp.Size = NumberSequence.new(0.3)
    sp.Color = ColorSequence.new(RGB(255, 200, 120))
    sp.EmissionDirection = Enum.NormalId.Front
    sp.Parent = h
    sp:Emit(24)
    Debris:AddItem(h, 3)
    if G.playSound then G.playSound("splash", p, 0.35) G.playSound("boom", p, 1.6) end
  end
  G.tossCount = 0   -- 测试用
  local function startToss(v)
    local tF = v.tF
    if not tF then return end
    local seed = tonumber(v.id) or 0
    if seed == 0 then for c in tostring(v.id):gmatch(".") do seed += string.byte(c) end end
    local rng = Random.new(seed * 7919 + 17)
    -- 照宣传片里调好的样子（用户 11-22 看片子：掀盖有点尴尬——原来往上 36～54 格 / 秒、乱转，飞七到十五米高像气球）：
    --   往上 20～27 格 / 秒（顶起三米上下）、往旁边 3～6 格 / 秒，绕一根横着的轴慢慢翻（每秒 1～1.6 弧度），落在车旁边歪着停住
    local ang = rng:NextNumber() * 2 * math.pi
    local side = V(math.cos(ang), 0, math.sin(ang))
    local hv = side * (3 + rng:NextNumber() * 3)
    local axis = V(-side.Z, (rng:NextNumber() - 0.5) * 0.4, side.X).Unit   -- 横轴：往哪边飞就朝哪边翻下去
    v.toss = {
      cf = tF, vel = V(hv.X, 20 + rng:NextNumber() * 7, hv.Z),
      w = axis * (1 + rng:NextNumber() * 0.6),   -- 角速度（弧度/秒，世界坐标）
      bounce = 0, rest = false,
      restTilt = CFrame.Angles((rng:NextNumber() - 0.5) * 0.5, 0, (rng:NextNumber() - 0.5) * 0.6),
    }
    G.tossCount += 1
    tossFx(tF.Position, v.def.cat == "tank")
  end
  local function stepToss(v, dt)
    local T = v.toss
    if not T or T.rest then return end
    dt = math.min(dt, 1 / 20)
    T.vel += V(0, -TOSS_G, 0) * dt
    local p = T.cf.Position + T.vel * dt
    local wm = T.w.Magnitude
    local rot = (wm > 1e-4) and CFrame.fromAxisAngle(T.w.Unit, wm * dt) or CFrame.new()
    local gy = math.max(Map.height(p.X, p.Z), -0.5)
    if p.Y < gy + 0.4 and T.vel.Y < 0 then   -- 砸到地上：弹一下（越弹越低），转得慢下来
      p = V(p.X, gy + 0.4, p.Z)
      T.bounce += 1
      landFx(p)
      if T.bounce >= 2 or math.abs(T.vel.Y) < 14 then   -- 砸下来顶多再颠一下就停住（原来弹三下）
        T.rest = true
        -- 停住：保留水平朝向，歪一点躺着（随机的倾角）
        local look = T.cf.LookVector
        local flat = V(look.X, 0, look.Z)
        flat = flat.Magnitude > 0.05 and flat.Unit or V(0, 0, -1)
        T.cf = CFrame.lookAt(p, p + flat) * T.restTilt
        return
      end
      T.vel = V(T.vel.X * 0.45, -T.vel.Y * 0.32, T.vel.Z * 0.45)
      T.w = T.w * 0.5
    end
    T.cf = CFrame.new(p) * rot * (T.cf - T.cf.Position)
  end
  G.stepToss = stepToss

  -- 履带印：薄薄一片深色的方块贴在地上，淡出后回收（对象池，最多 MAX_MARK 段）
  local MAX_MARK = 360
  local marks, markI = {}, 0
  local markFolder = Instance.new("Folder")
  markFolder.Name = "TrackMarks"
  markFolder.Parent = workspace
  local TweenService = game:GetService("TweenService")
  local markInfo = TweenInfo.new(14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
  function trackMark(cf, w, len)
    markI = markI % MAX_MARK + 1
    local m = marks[markI]
    if not m then
      m = Instance.new("Part")
      m.Anchored, m.CanCollide, m.CanQuery, m.CanTouch, m.CastShadow = true, false, false, false, false
      m.Material = Enum.Material.Ground
      m.Color = Color3.fromRGB(46, 40, 32)
      m.Parent = markFolder
      marks[markI] = m
    end
    if m:GetAttribute("Tw") then m:SetAttribute("Tw", nil) end
    m.Size = V(w, 0.1, len)
    m.CFrame = cf
    m.Transparency = 0.35
    TweenService:Create(m, markInfo, { Transparency = 1 }):Play()
  end
  G.trackMarkCount = function() return #marks end   -- 测试用

  ---------------------------------------------------------------- 载具：悬架

  -- 细碎的颠簸（土路、草地上轮子一跳一跳）：两层噪声，约 ±0.35 格
  local function bump(x, z)
    return 0.22 * math.noise(x / 5.3, z / 5.3, 0.37) + 0.12 * math.noise(x / 2.1, z / 2.1, 4.1)
  end
  local function angDiff(a, b) return (b - a + 180) % 360 - 180 end
  -- 两个 CFrame 差不多一样（位置差不到 0.0005 格、朝向差不到约 0.04°）；有一个是 nil 时两个都得是 nil
  local function sameCF(a, b)
    if a == nil or b == nil then return a == b end
    local dp = a.Position - b.Position
    if dp:Dot(dp) > 2.5e-7 then return false end
    return a.LookVector:Dot(b.LookVector) > 0.9999998 and a.UpVector:Dot(b.UpVector) > 0.9999998
  end

  local function stepVeh(v, dt, camPos)
    local em, d, M = v.em, v.def, v.M
    -- 车灯：有人开、没被打爆才亮
    local lit = (em:GetAttribute("Driver") or 0) ~= 0 and not v.wrecked
    if v.lit ~= lit and M.lamps then
      v.lit = lit
      for _, p in ipairs(M.lamps) do
        p.Transparency = lit and 0 or 0.75
        for _, L in ipairs(p:GetChildren()) do if L:IsA("Light") then L.Enabled = lit end end
      end
    end
    -- 大灯投影子很费（每盏灯每帧画一遍阴影图）：只有自己开的这辆的大灯投影子，别人的照样亮、不投影子
    local mineV = G.myVeh ~= nil and G.myVeh.em == em
    if v.lampShadow ~= mineV and M.lamps then
      v.lampShadow = mineV
      for _, p in ipairs(M.lamps) do
        for _, L in ipairs(p:GetChildren()) do if L:IsA("SpotLight") then L.Shadows = mineV end end
      end
    end
    local own = G.myVeh and G.myVeh.em == em and G.myVeh
    local target = own and own.root or v.root.CFrame
    -- 位置：自己开的直接用本地算的；别人的平滑跟
    if own then v.cf = target else v.cf = G.follow(v, target) end
    local base = v.cf * CF(0, -d.H / 2, 0)
    -- 速度、转弯（别人的车按位置变化估）
    local pos = base.Position
    if own then
      v.speed, v.steer, v.accel = own.speed, own.steer, own.accel or 0
    else
      local delta = pos - v.lastPos
      local sp = delta:Dot(base.LookVector) / math.max(dt, 1e-3)
      v.accel = (sp - v.speed) / math.max(dt, 1e-3)
      v.speed = v.speed + (sp - v.speed) * math.min(1, dt * 6)
      local _, yaw = base:ToEulerAnglesYXZ()
      local yr = angDiff(math.deg(v.lastYaw), math.deg(yaw)) / math.max(dt, 1e-3)
      v.steer = v.steer + (math.clamp(-yr / math.max(d.turn, 1), -1, 1) - v.steer) * math.min(1, dt * 6)
      v.lastYaw = yaw
    end
    v.lastPos = pos
    -- 炮塔、炮
    local ty, gp = em:GetAttribute("Ty") or 0, em:GetAttribute("Gp") or 0
    if own then ty, gp = own.ty, own.gp end
    if own then v.ty, v.gp = ty, gp else
      v.ty = v.ty + angDiff(v.ty, ty) * math.min(1, dt * 10)
      v.gp = v.gp + (gp - v.gp) * math.min(1, dt * 10)
    end
    if v.recoilT then
      v.recoilT += dt
      v.recoil = (v.recoilA or 0) * recoilCurve(v.recoilT, v.recoilBig)
      if v.recoilT > 0.7 then v.recoilT, v.recoil = nil, 0 end
    else
      v.recoil = 0
    end
    -- 遥控武器站：自己开的用本地算的转角，别人的读属性再平滑跟（用户：机枪也要能转动）
    if M.rpiv then
      local my, mp = em:GetAttribute("My") or 0, em:GetAttribute("Mp") or 0
      if own then v.my, v.mp = own.my or 0, own.mp or 0 else
        v.my = (v.my or 0) + angDiff(v.my or 0, my) * math.min(1, dt * 10)
        v.mp = (v.mp or 0) + (mp - (v.mp or 0)) * math.min(1, dt * 10)
      end
    end
    local far = (pos - camPos).Magnitude > 420
    -- 轮子：每个一个弹簧阻尼；远了不算（省事）
    local W = M.wheels
    local rough = 1
    local onWater = Map.height(pos.X, pos.Z) < -1.5
    -- 真地形（用户 11-22：坦克半截身子卡在地里）：别人的车（服务器按 Map.height 放的）0.2 秒左右量一次车底的真地面（Drive.lua 的 terrainLift），
    --   平滑着抬高 / 放低；自己开的车 Drive 已经算进去了。轮子、履带印也按同一个地面
    local lift = 0
    if own then lift = own.tLift or 0
    elseif not v.wrecked then
      v.tpT = (v.tpT or 0) - dt
      if v.tpT <= 0 then
        v.tpT = 0.18 + ((tonumber(v.id) or 0) % 7) * 0.01
        local _, yawB = base:ToEulerAnglesYXZ()
        v.tLiftT = (not far and not onWater and G.terrainLift) and (G.terrainLift(d, pos, yawB) or 0) or 0
      end
      v.tLift = (v.tLift or 0) + ((v.tLiftT or 0) - (v.tLift or 0)) * math.min(1, dt * 5)
      lift = v.tLift
      if math.abs(lift) > 1e-3 then base = base + V(0, lift, 0) end
    end
    local sF, nF, sB, nB, sL, nL, sR, nR, sum = 0, 0, 0, 0, 0, 0, 0, 0, 0
    if not far then
      for _, w in ipairs(W) do
        local wp = (base * CF(w.x, 0, w.z)).Position
        local gy = Map.height(wp.X, wp.Z) + lift
        local tgt
        local trv = M.travel or d.travel   -- 原模型的履带车：履带是死的，负重轮只能动一点
        if gy < -0.5 and onWater then tgt = -trv   -- 在水里：轮子垂下去
        else tgt = math.clamp(math.max(gy, -0.5) + bump(wp.X, wp.Z) * rough - wp.Y, -trv, trv) end
        local a = (tgt - w.dy) * 420 - w.vy * 26
        w.vy += a * dt
        w.dy = math.clamp(w.dy + w.vy * dt, -trv * 1.2, trv * 1.2)
        w.spin -= v.speed * dt / (w.rad or w.r)
        sum += w.dy
        if w.z < 0 then sF += w.dy nF += 1 else sB += w.dy nB += 1 end
        if w.x < 0 then sL += w.dy nL += 1 else sR += w.dy nR += 1 end
      end
    end
    local n = math.max(1, #W)
    local wb = math.max(4, (W[#W] and math.abs(W[#W].z - W[1].z)) or d.L * 0.7)
    local trk = math.max(3, d.W * 0.8)
    -- 车体：跟着轮子上下、俯仰、侧倾（弹簧）；起步抬头、刹车点头
    local tBob = sum / n * 0.55
    -- 起步抬头、刹车点头（战雷那样明显一点）
    local tPitch = ((nF > 0 and sF / nF or 0) - (nB > 0 and sB / nB or 0)) / wb * 0.7 + math.clamp((v.accel or 0) * 0.0022, -0.06, 0.06)
    local tRoll = ((nR > 0 and sR / nR or 0) - (nL > 0 and sL / nL or 0)) / trk * 0.7 + math.clamp(v.steer * v.speed * 0.0006, -0.04, 0.04)
    v.bobV += ((tBob - v.bob) * 160 - v.bobV * 14) * dt
    v.bob += v.bobV * dt
    v.pitchV += ((tPitch - v.pitch) * 120 - v.pitchV * 12) * dt
    v.pitch += v.pitchV * dt
    v.rollV += ((tRoll - v.roll) * 120 - v.rollV * 12) * dt
    v.roll += v.rollV * dt
    local hh = d.hullH
    local hullF = base * CF(0, v.bob, 0) * CF(0, hh / 2, 0) * CFrame.Angles(v.pitch, 0, v.roll) * CF(0, -hh / 2, 0)
    local tF = hullF * CF(M.tpiv or d.turret.pivot) * CFrame.Angles(0, -math.rad(v.ty), 0)
    if v.toss then   -- 掀飞了的炮塔自己飞（炮、机枪塔跟着它）
      stepToss(v, dt)
      tF = v.toss.cf
    end
    local gF = tF * CF(M.gpiv or d.gun.pivot) * CFrame.Angles(math.rad(v.gp), 0, 0) * CF(0, 0, v.recoil)
    local rF = M.rpiv and (tF * CF(M.rpiv) * CFrame.Angles(0, -math.rad(v.my or 0), 0)) or nil
    local rgF = (rF and M.rgpiv) and (rF * CF(M.rgpiv) * CFrame.Angles(math.rad(v.mp or 0), 0, 0)) or nil
    v.hullF, v.tF, v.gF, v.rF, v.rgF = hullF, tF, gF, rF, rgF
    local steerA = math.rad(28) * math.clamp(v.steer, -1, 1)
    local now = os.clock()
    -- 爆反块被炸掉（服务器写 EraX："3,7,12"）：那一块换成焦黑的空位（VehModels.eraBlown 新加的零件接到零件表后面）
    local ex = em:GetAttribute("EraX")
    if ex ~= v.eraX then
      v.eraX = ex
      v.putH = nil   -- 新接了零件：这一帧一定要摆
      for i in string.gmatch(ex or "", "%d+") do
        for _, it in ipairs(VM.eraBlown(M, tonumber(i))) do
          table.insert(M.parts, it)
          v.plist[#v.plist + 1] = it[1]
        end
      end
    end
    -- 省事（用户 11-19：游戏非常卡顿）：一辆车一两百个零件，原来每帧全部重摆。停着没动的（停车场、残骸、没人开的、
    --   自己停着没转炮塔）摆好一次就不再挪；420 格外的三帧挪一次（远处看不出来）
    if v.radar == nil then
      v.radar = {}
      for _, it in ipairs(M.parts) do if it[1]:GetAttribute("Radar") then v.radar[it[1]] = true end end
      v.hasRadar = next(v.radar) ~= nil
    end
    -- 扫雷犁（坦克改装，Kit.lua）：模型属性 Plow 1 放下、0.5 正在升、0 收好——放下是 0°，收好往上抬 14°（升起要 11 秒，这里按它慢慢抬）
    local plowMoving = false
    if M.plowPiv then
      local pa = em:GetAttribute("Plow")
      local want = (pa == 1) and 0 or math.rad(14)
      local cur = v.plowA or want
      local step = math.rad(14) / ((pa == 0.5) and 11 or 2.5) * dt
      if math.abs(want - cur) > 1e-4 then
        cur = cur + math.clamp(want - cur, -step, step)
        plowMoving = true
      end
      v.plowA = cur
    end
    local still = not plowMoving and not v.hasRadar and not (v.toss and not v.toss.rest) and v.recoil <= 0 and math.abs(v.speed) < 0.01
      and math.abs(v.steer - (v.putSteer or 1e9)) < 1e-4
      and sameCF(hullF, v.putH) and sameCF(tF, v.putT) and sameCF(gF, v.putG) and sameCF(rF, v.putR) and sameCF(rgF, v.putRG)
    if still then
      for _, w in ipairs(W) do if math.abs(w.vy) > 0.003 then still = false break end end
    end
    v.farN = (v.farN or 0) + 1
    if not still and (not far or own or v.farN % 3 == 0) then
      v.putH, v.putT, v.putG, v.putR, v.putRG, v.putSteer = hullF, tF, gF, rF, rgF, v.steer
      local plist, clist = v.plist, v.clist
      for i, it in ipairs(M.parts) do
        local grp, off = it[2], it[3]
        local cf
        if grp == "hull" then cf = hullF * off
        elseif grp == "turret" then
          cf = tF * off
          if v.radar[it[1]] then cf = cf * CFrame.Angles(0, now * 3, 0) end
        elseif grp == "gun" then cf = gF * off
        elseif grp == "rws" then cf = (rF or tF) * off
        elseif grp == "rwg" then cf = (rgF or rF or tF) * off
        elseif grp == "kit" then cf = (M.kpiv and (tF * CF(M.kpiv) * CFrame.Angles(math.rad(v.gp), 0, 0)) or tF) * off   -- 车顶加特林：跟着炮俯仰
        elseif grp == "plow" then cf = hullF * CF(M.plowPiv) * CFrame.Angles(v.plowA or 0, 0, 0) * off   -- 扫雷犁：绕车头下沿的转轴抬起 / 放下
        elseif grp == "wheel" then
          local w = W[it[4]]
          local wcf = base * CF(w.x, w.r + w.dy, w.z)
          if w.steer then wcf = wcf * CFrame.Angles(0, -steerA, 0) end
          cf = wcf * CFrame.Angles(w.spin, 0, 0) * off
        elseif grp == "seg" then
          local w = W[it[4]]
          cf = base * CF(0, w.dy, 0) * off
        else cf = hullF * off end
        clist[i] = cf
      end
      workspace:BulkMoveTo(plist, clist, Enum.BulkMoveMode.FireCFrameChanged)
      v.anchor.CFrame = hullF * CF(0, d.H + 1, 0)
      G.viewPuts = (G.viewPuts or 0) + #plist   -- 测试、性能面板用：一共摆了多少个零件
    end
    -- 扬尘：在陆地上开得快才有
    local land = not onWater
    if v.fireLight then v.fireLight.Brightness = 2.2 + math.random() * 1.8 end
    -- 扬尘按脚下的地面：土路、沙地最浓，草地淡一半，石头上更淡（每 0.3 秒看一次地面）
    v.dustT = (v.dustT or 0) - dt
    if v.dustT <= 0 then
      v.dustT = 0.3
      local mat = land and Map.material(pos.X, pos.Z, Map.height(pos.X, pos.Z), Map.slope(pos.X, pos.Z)) or nil
      local k, col = 0.5, nil
      if mat == Enum.Material.Ground then k, col = 1, Color3.fromRGB(168, 142, 104)
      elseif mat == Enum.Material.Sand then k, col = 1, Color3.fromRGB(206, 190, 150)
      elseif mat == Enum.Material.Rock or mat == Enum.Material.Slate then k, col = 0.3, Color3.fromRGB(150, 146, 138)
      else k, col = 0.45, Color3.fromRGB(150, 140, 112) end
      v.dustK = k
      if col and v.dustCol ~= col then
        v.dustCol = col
        for _, pe in ipairs(M.dust) do pe.Color = ColorSequence.new(col) end
      end
    end
    local rate = land and math.clamp((math.abs(v.speed) - 5) * 1.6, 0, 60) * (v.dustK or 0.5) or 0
    -- 侧滑、刚落地：扬尘更浓（自己开的车 Drive 给 slipA）
    if own and own.slipA then rate *= 1 + math.clamp(math.abs(math.sin(own.slipA)) * 4, 0, 2) end
    for _, pe in ipairs(M.dust) do if math.abs(pe.Rate - rate) > 0.5 then pe.Rate = rate end end
    -- 排气（VehModels）：怠速淡淡一缕；往前加速（踩油门、换挡后那一下）喷浓的；远了不放
    if M.exhaust and #M.exhaust > 0 then
      local acc = math.max(0, (v.accel or 0) * ((v.speed or 0) >= 0 and 1 or -1))
      local erate = far and 0 or (2 + math.clamp(acc * 0.9, 0, 26) + math.clamp(math.abs(v.speed or 0) * 0.05, 0, 3))
      for _, pe in ipairs(M.exhaust) do if math.abs(pe.Rate - erate) > 0.4 then pe.Rate = erate end end
    end
    -- 别人的车的发动机、履带声（用户 11-24：坦克的发动机声音做成战雷那样）：3D 的，挂在车的根部件上；380 格以内、有人开、没被毁才响；
    --   车速越快越尖越响、往前加速时更响（像在踩油门），履带车还有履带的哗啦声
    if not own then
      local dist = (pos - camPos).Magnitude
      -- 回差（A 挑的刺）：进 360 格才挂、出 400 格才拆——车在 380 格上下来回开时别每过一次线就拆了又建两个 Sound
      local running = lit and dist < (v.engS and 400 or 360) and v.root ~= nil and v.root.Parent ~= nil
      if running and not v.engS and G.realLoop then
        local tracked = d.arch == "tracked"
        local e1 = G.realLoop(tracked and "tankDrive" or "tankEngine", v.root)
        local e2 = tracked and G.realLoop("tankTracks", v.root) or nil
        for i, s in ipairs({ e1 or false, e2 or false }) do
          if s then
            s.Volume = 0
            s.RollOffMode = Enum.RollOffMode.InverseTapered
            s.RollOffMinDistance, s.RollOffMaxDistance = (i == 1) and 14 or 10, (i == 1) and 380 or 220
            pcall(function() s.TimePosition = math.random() * 2.5 end)   -- 几辆车别齐着响
          end
        end
        v.engS = { e1, e2 }
      end
      if v.engS then
        if not running then
          engSndOff(v)
        else
          local sp = math.clamp(math.abs(v.speed or 0) / math.max(d.speed or 30, 1), 0, 1)
          local acc = math.clamp(math.max(0, (v.accel or 0) * ((v.speed or 0) >= 0 and 1 or -1)) / 8, 0, 1)
          local e1, e2 = v.engS[1], v.engS[2]
          if e1 then
            e1.PlaybackSpeed = 0.72 + 0.5 * sp + 0.08 * acc
            e1.Volume = 0.35 + 0.5 * sp + 0.4 * acc
          end
          if e2 then
            e2.PlaybackSpeed = 0.55 + 0.75 * sp
            e2.Volume = math.clamp((sp - 0.02) * 4, 0, 1) * (0.25 + 0.5 * sp)
          end
        end
      end
    end
    -- 履带印（用户：坦克驾驶参考战雷）：履带车在地上开过去，两条履带底下每走 3.6 格留一段深色的印子，十几秒慢慢淡掉；
    --   离镜头 260 格以外、在水里、被毁了不留；全部车一共最多 MAX_MARK 段（旧的先收）
    if d.arch == "tracked" and land and not v.wrecked and not far and (pos - camPos).Magnitude < 260 then
      local lp = v.markPos
      if not lp then v.markPos = pos
      elseif (pos - lp).Magnitude >= 3.6 then
        local mid = (pos + lp) / 2
        local dir = pos - lp
        local L = dir.Magnitude
        local trackX = (d.rw and d.rw.x) or d.W * 0.36
        local tw = math.max(1.2, d.W * 0.16)
        for sgn = -1, 1, 2 do
          local o = base.RightVector * (sgn * trackX)
          local p = mid + o
          local gy = Map.height(p.X, p.Z) + lift
          trackMark(CFrame.lookAt(V(p.X, gy + 0.06, p.Z), V(p.X + dir.X, gy + 0.06, p.Z + dir.Z)), tw, L + 0.15)
        end
        v.markPos = pos
      end
    else
      v.markPos = nil
    end
    -- 被毁：烧
    if em:GetAttribute("Wreck") and not v.wrecked then
      v.wrecked = true
      -- 坦克被打爆：炮塔掀飞；别的有炮塔的车四成会（按编号定，大家看到的一样）
      if d.turret and not v.toss then
        local seed = tonumber(v.id) or 0
        local why = em:GetAttribute("WtWhy")   -- 战雷式伤害（服务器 Wt.lua）：只有弹药殉爆才掀炮塔，乘员打光、烧毁的车炮塔留着
        if why ~= nil then
          if why == "ammo" then startToss(v) end
        elseif d.cat == "tank" or Random.new(seed * 31 + 7):NextNumber() < 0.4 then startToss(v) end
      end
      M.fire.Rate, M.black.Rate = 30, 12
      if M.fire.Parent then   -- 夜里残骸的火光照亮周围（每帧闪一闪）
        local pl = Instance.new("PointLight")
        pl.Color, pl.Range, pl.Brightness, pl.Shadows = Color3.fromRGB(255, 140, 60), 28, 3, false   -- 投影子的只留最近的一处（stepFireShadows）
        pl.Parent = M.fire.Parent
        v.fireLight = pl
      end
      for _, it in ipairs(M.parts) do
        local part = it[1]
        if part:IsA("MeshPart") then   -- 原模型：贴图盖住颜色，烧黑要先把贴图去掉
          for _, sa in ipairs(part:GetChildren()) do if sa:IsA("SurfaceAppearance") then sa:Destroy() end end
          pcall(function() part.TextureID = "" end)
          part.Color = Color3.fromRGB(40, 38, 36)
        elseif part:IsA("BasePart") then part.Color = part.Color:Lerp(Color3.new(0.05, 0.05, 0.05), 0.65) end
      end
      for _, pe in ipairs(M.dust) do pe.Enabled = false end
      for _, pe in ipairs(M.exhaust or {}) do pe.Enabled = false end
    end
  end

  ---------------------------------------------------------------- 跟着实体文件夹

  local function watch(folder)
    for _, em in ipairs(folder:GetChildren()) do task.defer(add, em) end
    folder.ChildAdded:Connect(function(em) task.defer(add, em) end)
    folder.ChildRemoved:Connect(remove)
  end
  task.spawn(function()
    local f = workspace:WaitForChild("Ents", 60)
    if f then watch(f) end
  end)

  local cam = workspace.CurrentCamera
  -- 原模型是进服后陆续复制过来的：先用零件拼的样子建起来的，两秒看一次原模型齐了没有，齐了就重建（用户：很多飞机找不到建模）
  local function rebuild(em)
    local v = views[em]
    if not v then return end
    views[em] = nil
    if v.id then byId[v.id] = nil end
    engSndOff(v)
    if v.ext and v.ext.remove then G.try_(v.ext.remove, v) end
    if v.model then v.model:Destroy() end
    add(em)   -- 新建的 solidOn 是空的：下一帧离得近就重新挑实心零件
  end
  local impT = 0
  local function checkImports(dt)
    impT += dt
    if impT < 2 then return end
    impT = 0
    local list = {}
    for em, v in pairs(views) do
      local ok = false
      if v.kind == "veh" then
        ok = v.M ~= nil and not v.M.imported and v.def ~= nil and VM.importedFor(v.def) ~= nil
        if em:GetAttribute("Mods") ~= v.modsAttr or em:GetAttribute("TreeKey") ~= v.treeKey then ok = true end   -- 改装属性、科技树名字晚到了（或者换了）：按新的重建
      elseif v.ext and v.ext.importReady then ok = v.ext.importReady(v) == true end
      if ok and em.Parent then table.insert(list, em) end
    end
    for _, em in ipairs(list) do G.try_(rebuild, em) end
  end
  -- 实体对得上模型（用户：模型的实体和模型对不上）：服务器上的实体只有一个方盒（按型号表的长宽高），坦克是炮塔那么高一整块、
  --   飞机连翼尖都框不全、船连桅杆那么高——碰撞改在本机做：离自己的人近的车、飞机、船、工事、气垫艇，把看得见的零件设成实心
  --   （人的物理本来就在本机算，挡人按真正的外形；服务器的方盒只管挨打，不挡人）。很小的、几乎透明的、发光的、转的（旋翼、螺旋桨）、尾焰不算；
  --   自己正开着的那辆不算（人在里面）
  local SOLID_KIND = { veh = true, air = true, ship = true, fort = true, lcac = true }
  -- 一卡一卡（用户 11-18）：原来 280 格内的车、飞机、船全开着碰撞，这些零件每帧都在挪，物理引擎每帧都要重算——
  --   只在步行时、70 格内才开（走路撞得上的就这么近），一帧最多新开一辆（一下子来一群也不顿）
  local SOLID_IN, SOLID_OUT = 70, 95
  local solidBudget = 0
  local function solidSet(v, on)
    if (v.solidOn == true) == on then return end
    v.solidOn = on
    if on then
      local skip = {}
      local M = v.M
      if M then
        for _, key in ipairs({ "blades", "discs", "flames", "strobes", "lamps", "tvc" }) do
          for _, it in ipairs(M[key] or {}) do
            local p = (typeof(it) == "Instance") and it or (type(it) == "table" and (it.p or it[1])) or nil
            if typeof(p) == "Instance" then skip[p] = true end
          end
        end
      end
      local list = {}
      for _, p in ipairs(v.model:GetDescendants()) do
        if p:IsA("BasePart") and not skip[p] and p ~= v.anchor and p.Transparency < 0.9 and p.Material ~= Enum.Material.Neon
          and math.max(p.Size.X, p.Size.Y, p.Size.Z) >= 0.8 then
          p.CanQuery = true   -- 实心的零件 CanQuery 得开着（Roblox 的规定）
          p.CanCollide = true
          list[#list + 1] = p
        end
      end
      v.solidList = list
    else
      for _, p in ipairs(v.solidList or {}) do
        if p.Parent then
          p.CanCollide = false
          p.CanQuery = false
        end
      end
      v.solidList = nil
    end
  end
  G.viewSolid = solidSet
  local function stepSolid(v, here)
    if not SOLID_KIND[v.kind] or not v.model or not v.model.Parent then return end
    local mine = (G.drive and G.drive.em == v.em) or (G.fly and G.fly.em == v.em)
    local onFoot = not G.drive and not G.fly
    local p = (v.cf and v.cf.Position) or v.root.Position
    local d = here and (p - here).Magnitude or math.huge
    local want = onFoot and (not mine) and ((v.solidOn and d < SOLID_OUT) or (not v.solidOn and d < SOLID_IN))
    if want and not v.solidOn then
      if solidBudget <= 0 then return end   -- 这一帧已经开过一辆了：下一帧再开
      solidBudget -= 1
    end
    solidSet(v, want and true or false)
  end

  -- 残骸的火光（点光源）投影子很费（每盏灯每帧画一遍六面的阴影图）：只让离镜头最近、220 格内的那一处投影子，半秒挑一次
  local fireT = 0
  local function stepFireShadows(dt, camPos)
    fireT += dt
    if fireT < 0.5 then return end
    fireT = 0
    local best, bd = nil, 220 * 220
    for _, v in pairs(views) do
      local pl = v.fireLight
      if pl and pl.Parent then
        local dv = pl.Parent.Position - camPos
        local dd = dv:Dot(dv)
        if dd < bd then best, bd = pl, dd end
      end
    end
    for _, v in pairs(views) do
      local pl = v.fireLight
      if pl then
        local want = pl == best and (G.perfK or 1) >= 0.8
        if pl.Shadows ~= want then pl.Shadows = want end
      end
    end
  end

  function G.stepView(dt)
    solidBudget = 1
    stepDying()
    G.try_(stepFireShadows, dt, cam.CFrame.Position)
    G.try_(checkImports, dt)
    local myTeam = me:GetAttribute("Side")
    local camPos = cam.CFrame.Position
    local ch = me.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local here = hrp and hrp.Position or nil
    for em, v in pairs(views) do
      if not em.Parent then
        remove(em)
      else
        local hp, mx = em:GetAttribute("Hp") or 1, em:GetAttribute("MaxHp") or 1
        if hp ~= v.hpSeen or mx ~= v.mxSeen then
          v.hpSeen, v.mxSeen = hp, mx
          v.fill.Size = UDim2.fromScale(math.clamp(hp / math.max(1, mx), 0, 1), 1)
        end
        -- 自己开的车、船不挂血条：右下的载具面板有车体血量；坐进瞄准镜（第一人称）时镜头前也不会飘着自己的血条
        local mine = (G.myVeh ~= nil and G.myVeh.em == em) or (G.sail ~= nil and G.sail.em == em)
        local bbOn = hp < mx and hp > 0 and not mine
        if v.bb.Enabled ~= bbOn then v.bb.Enabled = bbOn end
        G.try_(stepSolid, v, here)
        if v.kind == "veh" then
          G.try_(stepVeh, v, dt, camPos)
        elseif v.ext then
          G.try_(v.ext.step, v, dt, camPos)
        else
          local target = v.root.CFrame
          v.cf = G.follow(v, target)
          local moved = v.fl.vel.Magnitude * 0.1   -- 走多快（腿、跳板的动画快慢）：按快照算的速度，一个更新间隔挪多远
          if v.kind == "lcac" and G.lcacUnderMine then   -- 自己正开着的这条气垫艇：按本地算的车底摆（不等服务器，和甲板上的车贴死）
            local mine = G.lcacUnderMine(em:GetAttribute("Carry"))
            if mine then v.cf = mine end
          end
          v.t += dt * math.clamp(moved * 2, 0, 12)
          for _, L in pairs(v.parts) do
            local off = L[2]
            if L[3] == "leg" then off = off * CFrame.Angles(math.sin(v.t * 1.2) * 0.7 * L[4], 0, 0)
            elseif L[3] == "ramp" and em:GetAttribute("Ramp") then off = off * CFrame.Angles(-1.3, 0, 0) end
            L[1].CFrame = v.cf * off
          end
        end
      end
    end
  end
  -- 跟服务器位置（用户 11-18：一卡一卡的）：服务器一秒只挪十来次（飞机按驾驶的人每秒报 15 次），原来每帧往「最新收到的位置」指数逼近——
  --   目标一跳一跳，跟的速度就一阵快一阵慢（十赫兹的顿挫，别人的车、飞机、船、士兵全是）。改成快照插值：记下最近几次收到的位置和收到的时刻，
  --   画面晚一点点（约 1.3 个更新间隔，按实际收到的间隔自己调），在前后两次之间按时间匀速插；跳得太远（传送、重生）直接过去；
  --   停了很久又动：先补一个「上一刻还在原地」的快照，从静止起步，不一下窜出去。返回插好的 CFrame；fl.vel 是按快照算的速度（格 / 秒）
  local FL_N = 6
  function G.follow(v, target, jump)
    local now = os.clock()
    local f = v.fl
    if not f then
      f = { n = 1, t = { now }, c = { target }, gap = 0.1, vel = Vector3.zero }
      v.fl = f
      return target
    end
    local n = f.n
    local last = f.c[n]
    if target ~= last then
      local g = now - f.t[n]
      if (target.Position - last.Position).Magnitude > (jump or 250) then   -- 传送、重生：清空、直接过去
        f.n, f.t, f.c, f.vel = 1, { now }, { target }, Vector3.zero
        return target
      end
      if g < 0.5 then
        f.gap += (math.clamp(g, 0.03, 0.3) - f.gap) * 0.2
      else   -- 停了很久才又动：补一个刚才还在原地的快照
        if n >= FL_N then table.remove(f.t, 1) table.remove(f.c, 1) n -= 1 end
        n += 1
        f.t[n], f.c[n] = now - f.gap, last
      end
      if n >= FL_N then table.remove(f.t, 1) table.remove(f.c, 1) n -= 1 end
      n += 1
      f.t[n], f.c[n] = now, target
      f.n = n
      local dtS = f.t[n] - f.t[n - 1]
      if dtS > 1e-3 then f.vel = f.vel:Lerp((f.c[n].Position - f.c[n - 1].Position) / dtS, 0.5) end
    elseif now - f.t[n] > 0.6 then
      f.vel = Vector3.zero   -- 好一阵没动了：停了
    end
    local rt = now - math.clamp(f.gap * 1.3, 0.06, 0.3)
    if rt >= f.t[n] then return f.c[n] end
    for i = n, 2, -1 do
      local t0 = f.t[i - 1]
      if t0 <= rt then
        return f.c[i - 1]:Lerp(f.c[i], (rt - t0) / math.max(1e-3, f.t[i] - t0))
      end
    end
    return f.c[1]
  end

  -- 准星射线打在「看得见的」实体上（评估后的修改：命中判定）：画面上的小兵、车是 G.follow 插值过的，比服务器的命中盒晚一截，
  --   原来准星射线打的是隐形命中盒，瞄着跑动的小兵身体开枪，射线从命中盒后面擦过去、曳光弹穿过人打在地上；
  --   现在按画面上的位置算（小兵用随姿势变的 Hit 盒，别的用 Root 盒），服务器那边按开枪的人看到的那一刻判定（Rewind.lua）。
  --   返回最近的交点、实体模型、距离；maxLen 以内没有就返回 nil
  local function slab(p, d, h, tmin, tmax)
    if math.abs(d) < 1e-9 then
      if p < -h or p > h then return nil end
      return tmin, tmax
    end
    local t1, t2 = (-h - p) / d, (h - p) / d
    if t1 > t2 then t1, t2 = t2, t1 end
    if t1 > tmin then tmin = t1 end
    if t2 < tmax then tmax = t2 end
    if tmin > tmax then return nil end
    return tmin, tmax
  end
  function G.viewRay(o, dir, maxLen)
    local u = dir.Unit
    local best, bestEm, bestT = nil, nil, maxLen
    for em, v in pairs(views) do
      local root = v.root
      if root and root.Parent and em.Parent and em:GetAttribute("Driver") ~= me.UserId then
        local hb = em:FindFirstChild("Hit") or root
        local cf = ((v.fl and v.cf) or root.CFrame) * root.CFrame:ToObjectSpace(hb.CFrame)   -- 有快照插值的按画面上的位置
        local size = hb.Size
        local rel = cf.Position - o
        local along = rel:Dot(u)
        local r = size.Magnitude / 2
        if along > -r and along < bestT + r and (rel - u * along).Magnitude <= r then
          local lo, ld = cf:PointToObjectSpace(o), cf:VectorToObjectSpace(u)
          local a, b = slab(lo.X, ld.X, size.X / 2, 0, bestT)
          if a then a, b = slab(lo.Y, ld.Y, size.Y / 2, a, b) end
          if a then a, b = slab(lo.Z, ld.Z, size.Z / 2, a, b) end
          if a and a < bestT then best, bestEm, bestT = o + u * a, em, a end
        end
      end
    end
    if best then return best, bestEm, bestT end
    return nil
  end

  -- 一辆车出错不影响别的
  function G.try_(f, ...)
    local ok, err = pcall(f, ...)
    if not ok and G.showError then G.showError("local view: " .. tostring(err)) end
  end
end

return View
