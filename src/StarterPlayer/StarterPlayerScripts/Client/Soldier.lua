-- Roblox全面大战场（客户端）——机器人士兵：Roblox 正常小人 + 程序动画
--   用户：士兵用 Roblox 正常小人的建模；给小兵加上动画和姿势；每个人要有自己的动作逻辑，不要一堆人一模一样
--   样子：服务器开服时生成一个默认的 R15 小人当模板（ReplicatedStorage.BotRig，Bots.lua），每个机器人克隆一个：按队伍迷彩上色、手套黑，
--     戴头盔和夜视仪、右臂臂章、一支步枪；没有模板（Studio 里连不上资源、模拟测试）用零件拼一个关节名字一样的小人（经典圆头、笑脸）
--   动作全是程序算的（不用 Roblox 的动画资源，那套是拿玩具的姿势）：躯干、头按姿势摆，双手按反向运动学握在枪上（右手握把、左手护木），
--     脚按步态踩在地上（在地上那一段脚不打滑）——站着端枪 / 低姿持枪、走、跑（枪斜挎在胸前）、蹲着走、单膝跪射、卧倒瞄准、匍匐、
--     换弹匣（旧弹匣掉地上）、扔手雷、小队长打手势、开枪后坐和枪口焰、挨打一缩、四种倒法（往后倒、往前扑、侧着瘫下去、转半圈倒）
--   姿势从服务器的属性来（Bots.lua）：St 姿势（0 站、1 蹲 / 跪、2 卧）、Aim 枪口俯仰（度，有目标时才有）、Act 动作（"r12" 换弹、"g13" 扔雷、
--     "s14" 打手势；字母后面是序号，变了才算一次新的）、Ride 在登陆艇上（蹲着不迈腿）、DieD 打死的那一枪从哪边来（度，0 正前）
--   每个人不一样：按实体编号给一套自己的参数——步频、站姿宽窄、身子前倾多少、低姿持枪的枪口高低、跪哪条腿、东张西望和做小动作
--     （扶头盔、看枪、回头看）的间隔、枪口晃的大小、默认倒法
--   远了降帧：300 格外每秒 15 次、700 格外每秒 4 次；1500 格外（跟着自动画质缩放）整个收起来
--   零件都不碰撞、不挡射线（子弹打的是服务器上的命中盒）
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Soldier = {}

function Soldier.init(G)
  local Config = G.Config
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local ANG = CFrame.Angles
  local PI = math.pi
  local UNIFORM = { atk = { RGB(150, 128, 92), RGB(110, 96, 70) }, def = { RGB(84, 104, 70), RGB(64, 78, 54) } }   -- 同 Round.lua 给玩家穿的
  local HELMET = { atk = RGB(96, 104, 72), def = RGB(146, 128, 96) }
  local SKIN, GLOVE, GUN = RGB(234, 194, 150), RGB(38, 38, 36), RGB(42, 44, 46)
  local HALF = 2.8   -- 服务器命中盒的中心在脚底上 2.8 格（趴下、蹲下也不变，变的是另一个命中零件）
  local UPV = V(0, 1, 0)
  local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
  local function lerp(a, b, t) return a + (b - a) * t end
  local function lerpV(a, b, t) return a + (b - a) * t end
  local function sm(t) t = clamp(t, 0, 1) return t * t * (3 - 2 * t) end
  local function ease(rate, dt) return 1 - math.exp(-rate * dt) end

  local function quiet(p, anchored)
    p.Anchored = anchored == true
    p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
    p.Massless = true
  end
  local function part(parent, size, color, mat, shape)
    local p = Instance.new("Part")
    if shape then p.Shape = shape end
    p.Size, p.Color = size, color
    p.Material = mat or Enum.Material.SmoothPlastic
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    quiet(p, false)
    p.Parent = parent
    return p
  end
  local function weld(p0, p1, c0)
    local w = Instance.new("Weld")
    w.Part0, w.Part1, w.C0 = p0, p1, c0
    w.Parent = p1
    return w
  end
  local function motor(name, p0, p1, c0, c1)
    local m = Instance.new("Motor6D")
    m.Name, m.Part0, m.Part1, m.C0, m.C1 = name, p0, p1, c0, c1 or CF()
    m.Parent = p1
    return m
  end

  -- 步枪（M4 的样子，全长 2.6 格 ≈ 0.85 米）：原点在握把顶上，枪口朝 −Z、顶上朝 +Y；挂在根零件上（RifleJ），每帧摆到该在的地方，双手去握它
  local RIF = { butt = V(0, 0.05, 0.74), grip = V(0, -0.02, 0.12), fore = V(0, -0.04, -0.8), mag = V(0, -0.38, -0.44), bolt = V(0.12, 0.24, -0.05),
    muzzle = V(0, 0.17, -1.92) }
  local function rifle(parent)
    local rr = part(parent, V(0.2, 0.2, 0.2), GUN)
    rr.Name, rr.Transparency = "RifleRoot", 1
    local function g(size, off, color, shape, mat)
      local p = part(parent, size, color or GUN, mat or Enum.Material.Metal, shape)
      weld(rr, p, off)
      return p
    end
    g(V(0.2, 0.3, 0.95), CF(0, 0.16, -0.3))                     -- 机匣
    g(V(0.2, 0.25, 0.62), CF(0, 0.17, -1.08))                   -- 护木
    g(V(0.52, 0.09, 0.09), CF(0, 0.17, -1.64) * ANG(0, PI / 2, 0), GUN, Enum.PartType.Cylinder)   -- 枪管
    g(V(0.18, 0.3, 0.62), CF(0, 0.07, 0.45))                    -- 枪托
    local mag = g(V(0.14, 0.42, 0.22), CF(0, -0.15, -0.42) * ANG(math.rad(-10), 0, 0))   -- 弹匣
    g(V(0.12, 0.32, 0.15), CF(0, -0.07, 0.04) * ANG(math.rad(18), 0, 0))                -- 握把
    g(V(0.14, 0.15, 0.34), CF(0, 0.38, -0.28), RGB(30, 31, 32))  -- 瞄准镜
    local fl = g(V(0.3, 0.3, 0.42), CF(RIF.muzzle + V(0, 0, -0.18)), RGB(255, 214, 140), Enum.PartType.Ball, Enum.Material.Neon)   -- 枪口焰
    fl.Name, fl.Transparency = "Flash", 1
    return rr, mag, fl
  end
  -- 头盔、夜视仪（头的大小按 1.2 格的 R15 头算，k 缩放）
  local function helmet(parent, head, team, k, y0)
    local col = HELMET[team] or HELMET.def
    local h = part(parent, V(1.42, 0.86, 1.5) * k, col, Enum.Material.Fabric)
    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.Sphere
    mesh.Parent = h
    weld(head, h, CF(0, y0 + 0.42 * k, 0.04 * k))
    weld(head, part(parent, V(1.46, 0.14, 1.54) * k, col:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Fabric), CF(0, y0 + 0.08 * k, 0.04 * k))
    weld(head, part(parent, V(0.34, 0.26, 0.16) * k, RGB(34, 36, 38), Enum.Material.Metal), CF(0, y0 + 0.42 * k, -0.74 * k))
    for _, sx in ipairs({ -1, 1 }) do   -- 夜视仪镜筒（翻上去的）
      weld(head, part(parent, V(0.4, 0.22, 0.22) * k, RGB(22, 24, 26), Enum.Material.Metal, Enum.PartType.Cylinder),
        CF(sx * 0.17 * k, y0 + 0.62 * k, -0.78 * k) * ANG(0, PI / 2, math.rad(70)))
    end
  end

  ---------------------------------------------------------------- 骨架：关节、骨长

  local JN = { "Root", "Waist", "Neck", "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist",
    "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }

  -- 两种小人共用：挂头盔、臂章、枪、手雷，量骨长
  local function finish(v, m, hrp, head, team, k, y0)
    local J = {}
    for _, d in ipairs(m:GetDescendants()) do
      if d:IsA("Motor6D") then J[d.Name] = { m = d, c0 = d.C0, c1 = d.C1, c1i = d.C1:Inverse() } end
    end
    for _, n in ipairs(JN) do if not J[n] then return false end end
    helmet(m, head, team, k, y0)
    local rua = J.RightShoulder.m.Part1
    weld(rua, part(m, V(rua.Size.X + 0.06, 0.3, rua.Size.Z + 0.06), Config.Teams[team or "atk"].color, Enum.Material.Neon), CF(0, 0.15, 0))
    local rr, mag, fl = rifle(m)
    v.rj = motor("RifleJ", hrp, rr, CF(0.6, -0.6, -1), CF())
    v.mag, v.flash = mag, fl
    local nade = part(m, V(0.38, 0.5, 0.38), RGB(66, 74, 56), Enum.Material.SmoothPlastic, Enum.PartType.Ball)   -- 手雷（扔的时候才露出来）
    nade.Name, nade.Transparency = "Nade", 1
    weld(J.RightWrist.m.Part1, nade, CF(0, -0.34, 0))
    v.nadeP = nade
    local function limb(a, b, c)
      local A, B, C = J[a], J[b], J[c]
      return { a = A, b = B, c = C, la = (B.c0.Position - A.c1.Position).Magnitude, lb = (C.c0.Position - B.c1.Position).Magnitude }
    end
    v.LA, v.RA = limb("LeftShoulder", "LeftElbow", "LeftWrist"), limb("RightShoulder", "RightElbow", "RightWrist")
    v.LL, v.RL = limb("LeftHip", "LeftKnee", "LeftAnkle"), limb("RightHip", "RightKnee", "RightAnkle")
    local foot = J.LeftAnkle.m.Part1
    v.ankH = J.LeftAnkle.c1.Position.Y + foot.Size.Y / 2   -- 脚放平时踝关节离地多高
    v.J = J
    v.gY = -v.hip   -- 地面（根零件坐标里）
    v.hipOff = J.LeftHip.c0.Position
    v.ltStand = v.gY + v.ankH + (v.LL.la + v.LL.lb) * 0.985 - v.hipOff.Y   -- 站着时下躯干中心多高（膝盖微屈，脚一定够得着地）
    return true
  end

  -- R15 小人（模板克隆）
  local function buildRig(v, tpl, team)
    local m = tpl:Clone()
    m.Name = "bot"
    local U = UNIFORM[team] or UNIFORM.atk
    local hrp = m:FindFirstChild("HumanoidRootPart")
    local head = m:FindFirstChild("Head")
    local hum = m:FindFirstChildOfClass("Humanoid")
    if not hrp or not head or not hum then
      m:Destroy()
      return false
    end
    local low = math.huge
    for _, p in ipairs(m:GetDescendants()) do
      if p:IsA("BasePart") then
        quiet(p, p == hrp)
        local n = p.Name
        if n == "Head" then p.Color = SKIN
        elseif string.find(n, "Hand") then p.Color = GLOVE
        elseif string.find(n, "Leg") or string.find(n, "Foot") or n == "LowerTorso" then p.Color = U[2]
        elseif string.find(n, "Arm") or n == "UpperTorso" then p.Color = U[1] end
        if p ~= hrp then low = math.min(low, p.Position.Y - p.Size.Y / 2) end
      elseif p:IsA("BodyColors") then
        p:Destroy()
      end
    end
    hrp.Transparency = 1
    hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    pcall(function() hum.EvaluateStateMachine = false end)   -- 不跑人物的状态机（站、跳、掉）：位置是这里摆的
    local an = hum:FindFirstChildOfClass("Animator")   -- 动作全是这里算的：Roblox 的动画器去掉，免得它每帧把关节写回去
    if an then an:Destroy() end
    local hip = hrp.Position.Y - low
    -- R15 的 HipHeight 就是根零件底面离地多高，按它算更靠得住（模板的关节没解算时零件位置不对，量出来偏小，小人被摆低、半截身子埋在地里）
    if hum.RigType == Enum.HumanoidRigType.R15 and (hum.HipHeight or 0) > 0.5 then hip = hum.HipHeight + hrp.Size.Y / 2 end
    v.model, v.anchor, v.hrp, v.hip, v.rig = m, head, hrp, math.clamp(hip, 2.4, 3.6), true
    if not finish(v, m, hrp, head, team, head.Size.Y / 1.2, 0) then
      m:Destroy()
      return false
    end
    return true
  end

  -- 零件拼的小人：关节名字、层级照 R15（同一套姿势代码），头是经典的圆头笑脸
  local function buildParts(v, team)
    local m = Instance.new("Model")
    m.Name = "bot"
    local U = UNIFORM[team] or UNIFORM.atk
    local function P(name, size, color)
      local p = part(m, size, color)
      p.Name = name
      return p
    end
    local hrp = P("HumanoidRootPart", V(2, 2, 1), U[1])
    hrp.Transparency, hrp.Anchored = 1, true
    local lt = P("LowerTorso", V(1.9, 0.45, 0.95), U[2])
    local ut = P("UpperTorso", V(2, 1.6, 1), U[1])
    local head = P("Head", V(2, 1, 1), SKIN)
    local hm = Instance.new("SpecialMesh")
    hm.MeshType = Enum.MeshType.Head
    hm.Scale = V(1.25, 1.25, 1.25)
    hm.Parent = head
    local face = Instance.new("Decal")
    face.Name = "face"
    face.Texture = "rbxasset://textures/face.png"
    face.Face = Enum.NormalId.Front
    face.Parent = head
    motor("Root", hrp, lt, CF(0, -0.8, 0), CF())
    motor("Waist", lt, ut, CF(0, 0.2, 0), CF(0, -0.8, 0))
    motor("Neck", ut, head, CF(0, 0.8, 0), CF(0, -0.55, 0))
    for _, s in ipairs({ -1, 1 }) do
      local side = (s < 0) and "Left" or "Right"
      local ua = P(side .. "UpperArm", V(0.95, 1.2, 0.95), U[1])
      local la = P(side .. "LowerArm", V(0.9, 1.1, 0.9), U[1])
      local hd = P(side .. "Hand", V(0.85, 0.32, 0.85), GLOVE)
      motor(side .. "Shoulder", ut, ua, CF(s * 1.5, 0.6, 0), CF(0, 0.4, 0))
      motor(side .. "Elbow", ua, la, CF(0, -0.55, 0), CF(0, 0.5, 0))
      motor(side .. "Wrist", la, hd, CF(0, -0.45, 0), CF(0, 0.1, 0))
      local ul = P(side .. "UpperLeg", V(0.95, 1.2, 0.95), U[2])
      local ll = P(side .. "LowerLeg", V(0.9, 1.1, 0.9), U[2])
      local ft = P(side .. "Foot", V(0.9, 0.3, 1.2), RGB(40, 38, 34))
      motor(side .. "Hip", lt, ul, CF(s * 0.5, -0.2, 0), CF(0, 0.5, 0))
      motor(side .. "Knee", ul, ll, CF(0, -0.45, 0), CF(0, 0.45, 0))
      motor(side .. "Ankle", ll, ft, CF(0, -0.4, 0), CF(0, 0.05, 0.15))
    end
    v.model, v.anchor, v.hrp, v.hip, v.rig = m, head, hrp, 3.0, false
    return finish(v, m, hrp, head, team, 1, 0)
  end

  ---------------------------------------------------------------- 每个人自己的参数

  local function rng(seed)
    local s = math.floor(seed) % 2147483647
    if s <= 0 then s += 2147483646 end
    return function()
      s = (s * 16807) % 2147483647
      return s / 2147483647
    end
  end
  local function personal(v)
    local n = tonumber(string.match(tostring(v.id or ""), "%d+")) or math.random(1, 999999)
    local r = rng(n * 7919 + 101)
    for _ = 1, 4 do r() end
    v.P = {
      cad = 0.9 + r() * 0.2,          -- 步频（步子大小跟着变：脚在地上那一段不打滑）
      width = 0.38 + r() * 0.26,      -- 站姿宽窄
      lean = -0.02 - r() * 0.08,      -- 身子前倾
      carry = r(),                    -- 低姿持枪：枪口往下多少
      look = 2.5 + r() * 6,           -- 东张西望的间隔（秒）
      fidget = 12 + r() * 24,         -- 小动作的间隔
      die = 1 + math.floor(r() * 4),  -- 默认倒法
      sway = 0.5 + r() * 1.0,         -- 枪口晃
      phase = r() * PI * 2,
      kneelL = r() < 0.25,            -- 跪左腿（多数跪右腿）
      cant = (r() - 0.5) * 0.12,      -- 枪身歪一点
      bob = 0.8 + r() * 0.5,          -- 跑起来上下颠的大小
    }
    v.ph = v.P.phase
  end

  ---------------------------------------------------------------- 反向运动学

  -- 一段两节的肢体（肩—肘—腕 / 髋—膝—踝）：父零件 P0（根零件坐标）不动，末端关节放到 W，肘 / 膝往 pole 那边弯；
  --   leg：腿（膝盖往前、小腿往后折）；返回上节、下节、末端零件的 CFrame（末端朝向给了 endRot 就用它，不然顺着下节）；
  --   够不着时伸直、末端停在够得着的地方
  local function ik(Lb, P0, W, pole, leg, endRot)
    local A, B, C = Lb.a, Lb.b, Lb.c
    local la, lb = Lb.la, Lb.lb
    local S = P0 * A.c0.Position
    local d = W - S
    local L = d.Magnitude
    local reach = (la + lb) * 0.97
    if L > reach and L > 1e-4 then   -- 够不着：肩膀往前探一点（最多 0.65 格，R15 的肩膀太宽、胳膊短），胳膊和身子错开一点看不出来
      local k = math.min(L - reach, 0.7)
      S += d * (k / L)
      d = W - S
      L = d.Magnitude
    end
    local du = (L > 1e-4) and d / L or V(0, -1, 0)
    L = clamp(L, math.abs(la - lb) + 0.02, (la + lb) * 0.999)
    local ca = clamp((la * la + L * L - lb * lb) / (2 * la * L), -1, 1)
    local sa = math.sqrt(math.max(0, 1 - ca * ca))
    local pp = pole - du * pole:Dot(du)
    if pp.Magnitude < 1e-4 then pp = (math.abs(du.Y) < 0.9) and UPV:Cross(du) or V(1, 0, 0) end
    pp = pp.Unit
    local E = S + du * (la * ca) + pp * (la * sa)
    local Wc = S + du * L
    local hx = leg and du:Cross(pp) or pp:Cross(du)   -- 关节的转轴（零件的 X）
    local y1 = (S - E).Unit
    local x1 = hx - y1 * hx:Dot(y1)
    x1 = (x1.Magnitude > 1e-4) and x1.Unit or V(1, 0, 0)
    local r1 = CFrame.fromMatrix(Vector3.zero, x1, y1, x1:Cross(y1))
    local y2 = (E - Wc).Unit
    local x2 = x1 - y2 * x1:Dot(y2)
    x2 = (x2.Magnitude > 1e-4) and x2.Unit or x1
    local r2 = CFrame.fromMatrix(Vector3.zero, x2, y2, x2:Cross(y2))
    local r3 = endRot or r2
    return CF(S - r1:VectorToWorldSpace(A.c1.Position)) * r1, CF(E - r2:VectorToWorldSpace(B.c1.Position)) * r2,
      CF(Wc - r3:VectorToWorldSpace(C.c1.Position)) * r3
  end
  -- 关节的 C0：让子零件正好在 P1（父零件在 P0）——Part1 = Part0 * C0 * C1⁻¹
  local function setJ(Jx, P0, P1) Jx.m.C0 = P0:Inverse() * P1 * Jx.c1 end
  local function fkCF(Jx, P0, rot) return P0 * Jx.c0 * rot * Jx.c1i end
  local function limbIK(v, Lb, P0, W, pole, leg, endRot)
    local a, b, c = ik(Lb, P0, W, pole, leg, endRot)
    setJ(Lb.a, P0, a)
    setJ(Lb.b, a, b)
    setJ(Lb.c, b, c)
    return c
  end

  ---------------------------------------------------------------- 动作的关键帧

  -- 换弹匣（2.4 秒）：左手 0 护木 → 弹匣（拔下来、掉地上）→ 胸前弹匣包 → 插上 → 拉枪机 → 回护木；{ 时刻, 跟着谁（"r" 枪 / "u" 上身）, 点 }
  local RELOAD = { { 0, "r", RIF.fore }, { 0.32, "r", RIF.mag }, { 0.55, "r", RIF.mag + V(0, -0.2, 0.05) }, { 0.95, "u", V(-0.42, -0.42, -0.62) },
    { 1.25, "u", V(-0.4, -0.36, -0.66) }, { 1.6, "r", RIF.mag + V(0, -0.06, 0) }, { 1.78, "r", RIF.mag }, { 2.0, "r", RIF.bolt }, { 2.4, "r", RIF.fore } }
  local function keyAt(K, a)
    if a <= K[1][1] then return K[1] , K[1], 0 end
    for i = 2, #K do
      if a <= K[i][1] then return K[i - 1], K[i], sm((a - K[i - 1][1]) / (K[i][1] - K[i - 1][1])) end
    end
    return K[#K], K[#K], 0
  end

  ---------------------------------------------------------------- 每帧的姿势

  local function stepPose(v, dt)
    local P, J = v.P, v.J
    local t = os.clock()
    local gY, ank = v.gY, v.ankH
    local st = v.st or 0
    v.wK = v.wK + (((st == 1) and 1 or 0) - v.wK) * ease((st == 1) and 7 or 5, dt)
    v.wP = v.wP + (((st == 2) and 1 or 0) - v.wP) * ease(2.6, dt)
    local wK, wP = v.wK, v.wP
    local sp = v.ride and 0 or (v.spd or 0)
    local mv = sm((sp - 0.6) / 2.4)       -- 在走
    local run = sm((sp - 9) / 6) * (1 - wK) * (1 - wP)   -- 在跑
    local wS = (1 - wK) * (1 - wP)
    -- 戒备（有目标、刚开过枪）：抵肩瞄准；不然低姿持枪，跑起来斜挎在胸前
    local alert = (v.aimSeen ~= nil and t - v.aimSeen < 2.5) or (v.fireT ~= nil and t - v.fireT < 3)
    v.wA = v.wA + ((alert and 1 or 0) - v.wA) * ease(alert and 8 or 2.2, dt)
    local wA = v.wA * (1 - 0.7 * run)
    local wPort = run * (1 - wA)
    v.aimS = v.aimS + ((v.aimP or 0) - v.aimS) * ease(6, dt)
    local aimP = v.aimS
    -- 步态：步频按速度、每人不一样；一步走多远 = 速度 ÷ 步频（脚在地上那一段正好跟身体走的一样多，不打滑）
    local cad
    if wP > 0.5 then cad = clamp(0.8 + sp * 0.3, 0.8, 1.7)
    elseif wK > 0.5 then cad = clamp(1.7 + sp * 0.2, 1.7, 3.0)
    else cad = clamp(2.4 + sp * 0.15, 2.4, 4.6) end
    cad = cad * P.cad
    if mv > 0.01 then v.ph = (v.ph + dt * cad * PI) % (PI * 2) end
    local duty = lerp(0.62, 0.36, sm((sp - 3) / 7)) + 0.12 * wK
    local half = math.min(duty * sp / math.max(cad, 0.5), 1.35)
    local lift = (lerp(0.16, 0.6, run) + 0.1 * mv) * (1 - wK * 0.4)
    local function foot(ph)
      local u = (ph % (PI * 2)) / (PI * 2)
      if u < duty then
        local s = u / duty
        return lerp(-half, half, s), 0, (s > 0.65) and -(s - 0.65) / 0.35 * 0.5 or 0   -- z（往后为正）、抬多高、脚掌俯仰（蹬地时脚跟抬）
      end
      local s = (u - duty) / (1 - duty)
      local a = sm(s / 0.3)   -- 刚抬脚时脚跟还抬着（接着蹬地那一下），往前摆时勾脚尖，落地前放平
      return lerp(half, -half, sm(s)), lift * math.sin(PI * s), -0.5 * (1 - a) + 0.25 * math.sin(PI * s) * a
    end
    local zl, yl, pl = foot(v.ph)
    local zr, yr, pr = foot(v.ph + PI)
    -- 骨盆：站（呼吸、重心左右换、走起来上下颠、跑起来前倾）/ 蹲跪 / 趴
    local bob = (lerp(0.03, 0.14, run) * P.bob) * (0.5 - 0.5 * math.cos(v.ph * 2)) * mv
    -- 步子迈开了腿要够得着地：骨盆按步长往下沉（弯着膝盖走，像战术行进），够不着才会脚打滑
    local reachL = (v.LL.la + v.LL.lb) * 0.95
    local hipH = v.ltStand + v.hipOff.Y - (gY + ank)
    local sink = math.max(0, hipH - math.sqrt(math.max(0, reachL * reachL - half * half))) * mv
    local shift = math.sin(t * 0.45 + P.phase) * 0.06 * (1 - mv)
    local ltStand = CF(shift, v.ltStand - 0.03 - bob - sink, 0) * ANG(P.lean - 0.2 * run - 0.04 * mv, 0.07 * math.sin(v.ph) * mv, 0.035 * math.sin(v.ph) * mv)
    local kn = P.kneelL and -1 or 1
    local kneeY = gY + 0.3
    local ltKneelY = kneeY + v.RL.la * 0.96 - v.hipOff.Y
    local ltKneel = CF(0, lerp(ltKneelY, v.ltStand - 0.62, mv), lerp(0.12, 0, mv)) * ANG(lerp(-0.06, -0.36, mv), 0, 0)
    local crawl = math.sin(v.ph) * mv
    local ltProne = CF(0.08 * crawl, gY + 0.56, 0.62) * ANG(-PI / 2 + 0.07, 0.07 * crawl, 0.05 * crawl)
    local LT = ltStand:Lerp(ltKneel, wK):Lerp(ltProne, wP)
    -- 动作（换弹、扔雷、手势、小动作）
    local act = v.act
    local aT = act and (t - act.t0) or 0
    if act and aT > act.dur then
      v.act, act = nil, nil
      if v.mag then v.mag.Transparency = 0 end
      if v.nadeP then v.nadeP.Transparency = 1 end
    end
    local throwK = (act and act.k == "g") and sm(math.min(aT / 0.15, (act.dur - aT) / 0.2)) or 0
    -- 挨打一缩（衰减的一下）
    local fl = v.flT and math.exp(-(t - v.flT) * 7) * math.min(1, (t - v.flT) * 30) or 0
    -- 上身：瞄准时侧过身（右肩往后，像真的端枪），头转回来对着前面；扔雷先往右拧再往左甩
    local twist = (-0.62 * wA - 0.3 * (1 - wA) + 0.2 * wPort) * (1 - wP)
    local throwTw = 0
    if throwK > 0 then throwTw = (aT < 0.55) and 0.5 * sm((aT - 0.2) / 0.3) or lerp(0.5, -0.55, sm((aT - 0.55) / 0.15)) end
    twist = lerp(twist, throwTw, throwK)
    local breath = math.sin(t * 1.7 + P.phase) * 0.012
    local wPitch = (aimP * 0.3 * wA) * (1 - wP) + 0.16 * wP + fl * 0.22 + 0.08 * wK * (1 - wP)
    local UT = LT * J.Waist.c0 * ANG(wPitch + breath, twist + 0.07 * math.sin(v.ph) * mv * wS, fl * 0.1 * (v.flS or 1)) * J.Waist.c1i
    -- 头：瞄准时贴腮（低一点、歪向右边的枪）；平时东张西望（每人自己的间隔）
    if t > (v.lookAt or 0) then
      v.lookAt = t + P.look * (0.5 + math.random())
      v.lookTo = (math.random() - 0.5) * 1.7
      v.lookUp = (math.random() - 0.6) * 0.3
    end
    local idle = (1 - wA) * (1 - mv)
    v.look = v.look + ((v.lookTo or 0) * idle - v.look) * ease(2.5, dt)
    local nPitch = (aimP * 0.5 - 0.16) * wA * (1 - wP) + (v.lookUp or 0) * idle + 1.05 * wP + fl * 0.25
    local nYaw = -twist * 0.9 + v.look
    local nRoll = -0.14 * wA * (1 - wP)
    -- 小动作：回头看
    if act and act.k == "f" and act.v == 3 then nYaw += 1.15 * sm(math.min(aT / 0.4, (act.dur - aT) / 0.4)) end
    if act and act.k == "f" and act.v == 2 then nPitch -= 0.4 * sm(math.min(aT / 0.3, (act.dur - aT) / 0.3)) end
    local HD = UT * J.Neck.c0 * ANG(nPitch, nYaw, nRoll) * J.Neck.c1i
    -- 枪：三种端法按权重混——低姿（枪托在胸口、枪口朝下）、跑（斜挎胸前，枪口朝左上）、瞄准（枪托抵右肩、枪口指向目标）
    local sw = P.sway * (1 - 0.6 * wA)
    local swy = math.noise(t * 0.7, P.phase) * 0.03 * sw
    local swp = math.noise(P.phase, t * 0.6) * 0.025 * sw
    local readyDir = UT:VectorToWorldSpace(V(-0.3, -math.sin(0.5 + 0.35 * P.carry), -math.cos(0.5 + 0.35 * P.carry)))
    local readyR = CFrame.lookAt(Vector3.zero, readyDir, UT.UpVector) * ANG(0, 0, P.cant)
    local ready = CF(UT * V(0.4, 0.1, -0.6) - readyR:VectorToWorldSpace(RIF.butt)) * readyR
    local portR = CFrame.lookAt(Vector3.zero, UT:VectorToWorldSpace(V(-0.55, 0.62, -0.56)), UT:VectorToWorldSpace(V(0.4, 0.4, -0.6)))
    local port = CF(UT * V(0.5, -0.45, -0.66) - portR:VectorToWorldSpace(RIF.butt)) * portR
    local aimDir = V(math.sin(swy) * math.cos(aimP), math.sin(aimP + swp), -math.cos(aimP) * math.cos(swy))
    if wP > 0.5 then aimDir = V(aimDir.X, math.sin(aimP * 0.5 + swp), aimDir.Z) end
    local aimR = CFrame.lookAt(Vector3.zero, aimDir, UPV) * ANG(0, 0, P.cant * 0.5)
    local aimC = CF(UT * V(0.7, 0.9, -0.5) - aimR:VectorToWorldSpace(RIF.butt)) * aimR
    local rif = ready:Lerp(port, wPort):Lerp(aimC, wA)
    -- 后坐：枪往后一顶、枪口往上跳；换弹时枪往里收、侧过来
    local rec = v.rec or 0
    if rec > 0.001 then rif = rif * CF(0, 0, 0.16 * rec) * ANG(0.08 * rec, 0, 0) end
    if act and act.k == "r" then
      local k = sm(math.min(aT / 0.3, (act.dur - aT) / 0.35))
      local rlR = CFrame.lookAt(Vector3.zero, UT:VectorToWorldSpace(V(-0.25, 0.3, -1)), UT.UpVector) * ANG(0, 0, 0.6)
      rif = rif:Lerp(CF(UT * V(0.45, 0.25, -0.75) - rlR:VectorToWorldSpace(RIF.grip)) * rlR, k)
    end
    if throwK > 0 then   -- 扔雷：枪换到左手、枪口朝下垂在左边
      local hangR = CFrame.lookAt(Vector3.zero, UT:VectorToWorldSpace(V(0.1, -0.85, -0.5)), UT:VectorToWorldSpace(V(0, 0.4, -1)))
      rif = rif:Lerp(CF(UT * V(-0.95, -0.35, -0.75) - hangR:VectorToWorldSpace(RIF.fore)) * hangR, throwK)
    end
    if v.dropR then rif = v.dropR end
    v.rj.C0 = rif
    -- 手：右手握把，左手护木；动作的时候换地方
    local rW = rif * RIF.grip
    local lW = rif * lerpV(RIF.fore, V(0, -0.12, -0.5), wP)   -- 趴着：左手托在弹匣前面（胳膊撑在地上够不到护木前头）
    if act and act.k == "r" then
      local a0, a1, k = keyAt(RELOAD, aT)
      local p0 = (a0[2] == "r") and rif * a0[3] or UT * a0[3]
      local p1 = (a1[2] == "r") and rif * a1[3] or UT * a1[3]
      lW = lerpV(p0, p1, k)
      if aT > 0.5 and aT < 1.55 and v.mag and v.mag.Transparency < 1 then
        v.mag.Transparency = 1
        if not act.dropped then   -- 旧弹匣掉到地上
          act.dropped = true
          local d = v.mag:Clone()
          d.Transparency = 0
          d.Anchored = true
          d.Parent = v.model.Parent
          local p0w = (v.hrp.CFrame * rif * CF(RIF.mag)).Position
          local gy = (v.hrp.CFrame * V(0, gY + 0.1, 0)).Y
          d.CFrame = CF(p0w)
          pcall(function()
            game:GetService("TweenService"):Create(d, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
              { CFrame = CF(p0w.X, gy, p0w.Z) * ANG(PI / 2, math.random() * 6, 0) }):Play()
          end)
          Debris:AddItem(d, 6)
        end
      elseif aT >= 1.55 and v.mag and v.mag.Transparency > 0 then
        v.mag.Transparency = 0
      end
    elseif act and act.k == "g" then
      -- 右手：掏雷（胸前）→ 举到脑后 → 往前上方甩出去（0.62 秒出手）→ 往下收
      local K = { { 0, V(0.3, -0.3, -0.7) }, { 0.22, V(0.35, -0.35, -0.68) }, { 0.52, V(1.25, 1.35, 0.55) }, { 0.66, V(0.45, 1.25, -1.65) }, { 0.9, V(0.15, -0.2, -1.2) }, { 1.1, V(0.3, -0.3, -0.7) } }
      local a0, a1, k = keyAt(K, aT)
      rW = rW:Lerp(UT * lerpV(a0[2], a1[2], k), throwK)
      if v.nadeP then v.nadeP.Transparency = (aT > 0.18 and aT < 0.64) and 0 or 1 end
    elseif act and act.k == "s" then
      -- 手势（往前推进）：左手离开枪，举起来往前劈两下
      local K = { { 0, nil }, { 0.25, V(-0.85, 1.55, -1.25) }, { 0.45, V(-0.85, 0.85, -1.85) }, { 0.65, V(-0.85, 1.5, -1.3) }, { 0.85, V(-0.85, 0.85, -1.85) }, { 1.2, nil } }
      local a0, a1, k = keyAt(K, aT)
      local p0, p1 = a0[2] and UT * a0[2] or lW, a1[2] and UT * a1[2] or lW
      lW = lerpV(p0, p1, k)
    elseif act and act.k == "f" and act.v == 1 then   -- 小动作：扶一下头盔
      local k = sm(math.min(aT / 0.35, (act.dur - aT) / 0.35))
      lW = lerpV(lW, HD * V(-0.75, 0.45, -0.1), k)
    end
    -- 胳膊：肘往外下方（瞄准时右肘抬起来）；趴着时肘撑在地上
    local rPole = UT:VectorToWorldSpace(V(1, lerp(-1, -0.35, wA), 0.35))
    local lPole = UT:VectorToWorldSpace(V(-0.8, -1.2, 0.15))
    if wP > 0.5 then rPole, lPole = V(0.6, -1, 0.3), V(-0.6, -1, 0.3) end
    limbIK(v, v.RA, UT, rW, rPole, false, nil)
    limbIK(v, v.LA, UT, lW, lPole, false, nil)
    -- 腿：站 / 走（步态）、蹲跪（跪的那条腿膝盖着地、脚背贴地）、趴（伸直、脚尖点地、匍匐时轮流收一条腿）
    local hxL, hxR = J.LeftHip.c0.Position.X, J.RightHip.c0.Position.X
    local wide = (P.width - 0.5) * (1 - run)
    local stag = 0.2 * (1 - mv)   -- 站着：左脚在前一点（端枪的站法）
    local function toe(p) return (p < 0) and 0.72 * math.sin(-p) or 0.22 * math.sin(p) end   -- 蹬地绕脚尖、勾脚尖绕脚跟：踝关节跟着抬
    local sL = V(hxL - wide * 0.5 + run * 0.14, gY + ank + (yl + toe(pl)) * mv, lerp(-stag, zl, mv))
    local sR = V(hxR + wide * 0.5 - run * 0.14, gY + ank + (yr + toe(pr)) * mv, lerp(stag * 0.5, zr, mv))
    local flatL = ANG(lerp(0, pl, mv), lerp(0.12, 0, mv), 0)
    local flatR = ANG(lerp(0, pr, mv), lerp(-0.25, 0, mv), 0)
    local kx, fx = (kn > 0) and hxR or hxL, (kn > 0) and hxL or hxR
    local kneeBack = V(kx * 1.05, gY + 0.26, 0.12 + v.RL.lb * 0.96)
    local kneeFront = V(fx * 1.15, gY + ank, -0.85)
    local cL = V(hxL * 1.1, gY + ank + yl * mv * 0.7, zl * 0.8)
    local cR = V(hxR * 1.1, gY + ank + yr * mv * 0.7, zr * 0.8)
    local kL = lerpV((kn > 0) and kneeFront or kneeBack, cL, mv)
    local kR = lerpV((kn > 0) and kneeBack or kneeFront, cR, mv)
    local kRotBack = ANG(2.9, 0, 0)   -- 跪着的那只脚：脚背贴地、脚掌朝上朝后
    local kRL = (kn > 0) and ANG(0, 0, 0) or kRotBack
    local kRR = (kn > 0) and kRotBack or ANG(0, 0, 0)
    local hipW = LT * V(0, v.hipOff.Y, 0)
    local legL = (v.LL.la + v.LL.lb) * 0.97
    local pL = V(hxL * 1.3 + 0.35 * math.max(0, crawl), gY + 0.34, hipW.Z + legL - 0.7 * math.max(0, crawl))
    local pR = V(hxR * 1.3 - 0.35 * math.max(0, -crawl), gY + 0.34, hipW.Z + legL - 0.7 * math.max(0, -crawl))
    local pRot = ANG(-2.84, 0, 0)   -- 趴着：脚尖朝后、脚背贴地
    local tL = lerpV(lerpV(sL, kL, wK), pL, wP)
    local tR = lerpV(lerpV(sR, kR, wK), pR, wP)
    local rL = flatL:Lerp(kRL:Lerp(flatL, mv), wK):Lerp(pRot, wP)
    local rR = flatR:Lerp(kRR:Lerp(flatR, mv), wK):Lerp(pRot, wP)
    local poleL = lerpV(V(-0.2, -0.15 * wK, -1), V(0.25 * math.max(0, crawl), -1, 0.1), wP)
    local poleR = lerpV(V(0.2, -0.15 * wK, -1), V(-0.25 * math.max(0, -crawl), -1, 0.1), wP)
    if kn > 0 then poleR = lerpV(poleR, V(0, -1, -0.5), wK * (1 - mv) * (1 - wP)) else poleL = lerpV(poleL, V(0, -1, -0.5), wK * (1 - mv) * (1 - wP)) end
    limbIK(v, v.LL, LT, tL, poleL, true, rL)
    limbIK(v, v.RL, LT, tR, poleR, true, rR)
    -- 躯干、头
    setJ(J.Root, CF(), LT)
    J.Waist.m.C0 = LT:Inverse() * UT * J.Waist.c1
    J.Neck.m.C0 = UT:Inverse() * HD * J.Neck.c1
    -- 枪口焰：开枪后一闪
    if v.flash then
      local on = v.fireT ~= nil and t - v.fireT < 0.05
      v.flash.Transparency = on and 0.1 or 1
      if on then v.flash.Size = V(0.26, 0.26, 0.36) * (0.8 + math.random() * 0.6) end
    end
    v.rec = (v.rec or 0) * math.exp(-dt * 16)
  end

  ---------------------------------------------------------------- 倒下

  -- 四种倒法：1 往后倒（膝盖一软、仰面倒下）、2 往前扑（跪下、脸朝下扑倒）、3 侧着瘫下去（蜷着腿）、4 转半圈仰面倒
  --   趴着被打死的：头一垂、胳膊一松；终点姿势用正向运动学（关节角）算一次，过程按关节的 C0 插值
  local function fkSet(v, LT, A)
    local J = v.J
    local out = { Root = LT * J.Root.c1 }
    local function fkv(name, a) out[name] = J[name].c0 * ANG(a[1], a[2], a[3]) end
    fkv("Waist", A.waist)
    fkv("Neck", A.neck)
    fkv("LeftShoulder", A.lsh)
    fkv("RightShoulder", A.rsh)
    fkv("LeftElbow", A.lel)
    fkv("RightElbow", A.rel)
    fkv("LeftWrist", { 0, 0, 0 })
    fkv("RightWrist", { 0, 0, 0 })
    fkv("LeftHip", A.lhp)
    fkv("RightHip", A.rhp)
    fkv("LeftKnee", A.lkn)
    fkv("RightKnee", A.rkn)
    fkv("LeftAnkle", A.lan or { 0.5, 0, 0 })
    fkv("RightAnkle", A.ran or { 0.5, 0, 0 })
    return out
  end
  local function deathPlan(v)
    local P, gY = v.P, v.gY
    local kind = P.die
    local dd = v.em and v.em:GetAttribute("DieD")
    if type(dd) == "number" then
      local a = math.abs(dd)
      if a < 55 then kind = (P.die % 2 == 0) and 4 or 1
      elseif a > 125 then kind = 2
      else kind = 3 end
    end
    local side = (type(dd) == "number" and dd > 0) and -1 or 1   -- 往挨打的另一边倒
    local mid, fin
    if (v.wP or 0) > 0.5 then
      local LT = CF(0, gY + 0.5, 0.62) * ANG(-PI / 2 + 0.03, 0.15 * side, 0.12 * side)
      fin = fkSet(v, LT, { waist = { 0.02, 0, 0 }, neck = { 0.55, 0.9 * side, 0 }, lsh = { 2.6, 0, 0.5 }, rsh = { 2.2, 0, -0.7 }, lel = { 0.3, 0, 0 }, rel = { 0.6, 0, 0 },
        lhp = { 0, 0, -0.12 }, rhp = { 0, 0, 0.18 }, lkn = { -0.2, 0, 0 }, rkn = { -0.05, 0, 0 }, lan = { -1.2, 0, 0 }, ran = { -1.2, 0, 0 } })
      return { kind = 0, fin = fin, t1 = 0.01, t2 = 0.45 }
    end
    local kneelLT = CF(0, gY + 0.32 + v.RL.la * 0.96 - v.hipOff.Y, 0.15)
    if kind == 1 or kind == 4 then
      mid = fkSet(v, kneelLT * ANG(0.25, 0, 0), { waist = { 0.25, 0, 0 }, neck = { 0.4, 0, 0 }, lsh = { 0.9, 0, 0.6 }, rsh = { 1.1, 0, -0.5 }, lel = { 0.5, 0, 0 }, rel = { 0.6, 0, 0 },
        lhp = { 0.9, 0, 0 }, rhp = { 0.6, 0, 0 }, lkn = { -1.6, 0, 0 }, rkn = { -1.9, 0, 0 } })
      local spin = (kind == 4) and 1.5 * side or 0.2 * side
      fin = fkSet(v, CF(0.4 * side, gY + 0.5, 1.6) * ANG(0, spin, 0) * ANG(PI / 2 - 0.06, 0, 0.05 * side), { waist = { 0.08, 0, 0 }, neck = { -0.1, 1.0 * side, 0 },
        lsh = { 0.4, 0, 1.45 }, rsh = { 0.9, 0, -1.2 }, lel = { 0.5, 0, 0 }, rel = { 0.25, 0, 0 },
        lhp = { 0.35, 0, -0.2 }, rhp = { 0.1, 0, 0.25 }, lkn = { -0.8, 0, 0 }, rkn = { -0.2, 0, 0 }, lan = { 0.6, 0, 0 }, ran = { 0.8, 0, 0 } })
    elseif kind == 2 then
      mid = fkSet(v, CF(0, gY + 0.32 + v.LL.la * 0.95 - v.hipOff.Y, 0.25) * ANG(-0.35, 0, 0), { waist = { -0.35, 0, 0 }, neck = { -0.3, 0, 0 },
        lsh = { 0.3, 0, -0.1 }, rsh = { 0.5, 0, 0.1 }, lel = { 0.2, 0, 0 }, rel = { 0.2, 0, 0 },
        lhp = { 1.3, 0, 0 }, rhp = { 1.3, 0, 0 }, lkn = { -1.5, 0, 0 }, rkn = { -1.5, 0, 0 }, lan = { -1.0, 0, 0 }, ran = { -1.0, 0, 0 } })
      fin = fkSet(v, CF(0.2 * side, gY + 0.5, -1.3) * ANG(0, 0.3 * side, 0) * ANG(-PI / 2 + 0.05, 0, 0), { waist = { 0.02, 0, 0 }, neck = { 0.5, 1.25 * side, 0 },
        lsh = { 2.4, 0, 0.9 }, rsh = { 0.4, 0, -0.35 }, lel = { 1.2, 0, 0 }, rel = { 0.2, 0, 0 },
        lhp = { 0, 0, -0.15 }, rhp = { 0.5, 0, 0.3 }, lkn = { -0.1, 0, 0 }, rkn = { -1.0, 0, 0 }, lan = { -1.3, 0, 0 }, ran = { -1.1, 0, 0 } })
    else
      mid = fkSet(v, kneelLT * ANG(-0.2, 0, 0.25 * side), { waist = { -0.3, 0, 0.2 * side }, neck = { -0.5, 0, 0.3 * side }, lsh = { 0.3, 0, -0.2 }, rsh = { 0.3, 0, 0.2 }, lel = { 0.6, 0, 0 }, rel = { 0.6, 0, 0 },
        lhp = { 1.2, 0, 0 }, rhp = { 1.0, 0, 0 }, lkn = { -1.7, 0, 0 }, rkn = { -1.8, 0, 0 } })
      fin = fkSet(v, CF(1.1 * side, gY + 0.62, 0.35) * ANG(0, -0.4 * side, 0) * ANG(0.15, 0, PI / 2 * 0.96 * side), { waist = { -0.35, 0, 0 }, neck = { -0.3, 0, 0.35 * side },
        lsh = { 1.1, 0, -0.3 * side }, rsh = { 0.8, 0, 0.2 * side }, lel = { 1.0, 0, 0 }, rel = { 0.9, 0, 0 },
        lhp = { 1.0, 0, 0 }, rhp = { 0.7, 0, 0 }, lkn = { -1.4, 0, 0 }, rkn = { -1.1, 0, 0 } })
    end
    return { kind = kind, mid = mid, fin = fin, t1 = (kind == 2) and 0.32 or 0.26, t2 = (kind == 2) and 0.82 or 0.9, side = side }
  end

  ---------------------------------------------------------------- 接到 View.lua（G.viewKind.bot）

  local dying = {}
  G.viewKind = G.viewKind or {}
  local function attrs(v)
    local em = v.em
    v.st = em:GetAttribute("St") or 0
    v.ride = em:GetAttribute("Ride") == true
    local a = em:GetAttribute("Aim")
    if type(a) == "number" then
      v.aimP = math.rad(clamp(a, -60, 60))
      v.aimSeen = os.clock()
    end
    local act = em:GetAttribute("Act") or ""
    if v.actSeen == nil then v.actSeen = act end   -- 刚生成就带着的旧动作不放
    if type(act) == "string" and act ~= v.actSeen then
      v.actSeen = act
      local k = string.sub(act, 1, 1)
      if k == "r" then v.act = { k = "r", t0 = os.clock(), dur = 2.45 }
      elseif k == "g" then v.act = { k = "g", t0 = os.clock(), dur = 1.15 } v.fireT = os.clock()
      elseif k == "s" then v.act = { k = "s", t0 = os.clock(), dur = 1.2 } end
    end
    local hp = em:GetAttribute("Hp") or 1
    if v.hpSeen2 and hp < v.hpSeen2 and hp > 0 then v.flT, v.flS = os.clock(), (math.random() < 0.5) and -1 or 1 end
    v.hpSeen2 = hp
  end
  G.viewKind.bot = {
    build = function(v, em, team)
      local tpl = RS:FindFirstChild("BotRig")
      local ok = tpl and buildRig(v, tpl, team)
      if not ok then ok = buildParts(v, team) end
      if not ok then return false end
      personal(v)
      v.spd, v.lastP = 0, v.root.CFrame.Position
      v.cf = v.root.CFrame
      v.wK, v.wP, v.wA, v.aimS, v.look, v.acc = 0, 0, 0, 0, 0, 0
      attrs(v)
      v.wK = (v.st == 1) and 1 or 0
      v.wP = (v.st == 2) and 1 or 0
      v.hrp.CFrame = v.cf * CF(0, v.hip - HALF, 0)
      G.try_(stepPose, v, 0)
      return true
    end,
    step = function(v, dt, camPos)
      local target = v.root.CFrame
      local p = target.Position
      -- 远了（2600 格外，跟着自动画质 G.perfK 缩放；原来 1500，用户 11-22 视野改成无限远：狙击镜、望远镜里一公里外的人也看得见）：
      --   整个人收起来（不画、动作也不算）；回到范围里再摆回去（700 格外的动作本来就四分之一秒才算一次）
      local dist = (p - camPos).Magnitude
      local hideD = 2600 * (G.perfK or 1)
      if dist > hideD then
        if not v.hidden then
          v.hidden, v.home = true, v.model.Parent
          v.model.Parent = nil
        end
        v.cf, v.lastP, v.spd, v.fl = target, p, 0, nil   -- 插值的快照也扔掉：回到范围里从当时的位置重新开始
        return
      elseif v.hidden and dist < hideD * 0.95 then
        v.hidden = false
        v.model.Parent = v.home
      end
      -- 位置：快照插值（View.lua G.follow：匀速走）
      v.cf = G.follow(v, target)
      v.lastP = p
      local fv = v.fl.vel
      v.spd = v.spd + (V(fv.X, 0, fv.Z).Magnitude - v.spd) * math.min(1, dt * 5)
      v.hrp.CFrame = v.cf * CF(0, v.hip - HALF, 0)
      -- 动作：远了降帧
      v.acc += dt
      local gap = (dist > 700 * (G.perfK or 1)) and 0.25 or ((dist > 300) and 1 / 15 or 0)
      if v.acc < gap then return end
      local d2 = v.acc
      v.acc = 0
      attrs(v)
      stepPose(v, math.min(d2, 0.3))
    end,
    -- 开枪（Fx 的 gun 带着开枪的实体编号）：后坐、枪口焰，之后几秒保持端枪
    recoil = function(v)
      v.fireT = os.clock()
      v.rec = math.min(1.4, (v.rec or 0) + 1)
    end,
    -- 死了：按倒法倒下，枪脱手掉地上；8 秒后消失（最后一秒沉到地下）；返回 true = 模型自己收（View.lua 不马上删）
    remove = function(v)
      if (v.em:GetAttribute("Hp") or 1) > 0 then return false end
      if v.bb then v.bb:Destroy() end
      local ok, plan = pcall(deathPlan, v)
      if not ok or not plan then return false end
      local c0 = {}
      for n, Jx in pairs(v.J) do c0[n] = Jx.m.C0 end
      plan.c0, plan.t0, plan.cf = c0, os.clock(), v.cf
      plan.rif0 = v.rj.C0
      local s = plan.side or 1
      plan.rif1 = CF(0.9 * s + (math.random() - 0.5), v.gY + 0.14, -0.4 + math.random() * 1.2) * ANG(0, math.random() * 6.28, PI / 2 * s)
      v.flash.Transparency = 1
      if v.nadeP then v.nadeP.Transparency = 1 end
      table.insert(dying, { v = v, plan = plan })
      return true
    end,
  }
  -- 枪口在哪（Fx 画机器人开枪的曳光从枪口出来，不从头上）
  function G.botMuzzle(id)
    local v = G.viewById and G.viewById(id)
    if not v or not v.rj or v.hidden then return nil end
    return (v.hrp.CFrame * v.rj.C0 * CF(RIF.muzzle)).Position
  end
  G.frameConn("Soldier", function()
    local t = os.clock()
    for i = #dying, 1, -1 do
      local d = dying[i]
      local v, P = d.v, d.plan
      local a = t - P.t0
      if a > 8 or not v.model.Parent then
        v.model:Destroy()
        table.remove(dying, i)
      else
        -- 两段：先软下去（膝盖一软 / 跪下），再倒（像被重力拽下去，越倒越快），最后落地轻轻一弹
        local from, to, k
        if P.mid and a < P.t1 then
          from, to, k = P.c0, P.mid, sm(a / P.t1)
        else
          local a2 = (a - (P.mid and P.t1 or 0)) / (P.t2 - (P.mid and P.t1 or 0))
          from, to = P.mid or P.c0, P.fin
          k = clamp(a2, 0, 1)
          k = k * k
          if a2 > 1 then k = 1 + 0.04 * math.sin(math.min(1, (a2 - 1) * 2.5) * PI) end
        end
        for n, Jx in pairs(v.J) do
          local c1 = to[n]
          if c1 then Jx.m.C0 = from[n]:Lerp(c1, k) end
        end
        local kr = clamp(a / 0.5, 0, 1)
        v.rj.C0 = P.rif0:Lerp(P.rif1, kr * kr)
        local sink = (a > 7) and (a - 7) * 2.2 or 0
        v.hrp.CFrame = P.cf * CF(0, v.hip - HALF - sink, 0)
      end
    end
  end)
end

return Soldier
