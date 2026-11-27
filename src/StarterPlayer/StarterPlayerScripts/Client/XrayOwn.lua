-- 全面大战场（客户端）——透视自己的车（按住 X 的 X 光）
--   用户 11-26：「x透视做的非常潦草 且没有显示」「x应该是摁住显示3d 松手就恢复原样 然后 不同区域要有不同颜色标识 发动机 弹药箱 成员 爆反等等」
--   用户 11-27：「x 透视不够细节」——里面照真车的布置画成一眼认得出来的样子（颜色、字体用 Theme，不照搬别的游戏的美术）：
--   · 乘员：零件拼的人（头、躯干、骨盆、上臂、前臂、大腿、小腿、脚），按角色摆姿势——驾驶员半躺着握操纵杆、炮长坐着脸贴瞄准镜目镜、
--     车长坐得高、头伸进指挥塔，装填手站着朝着炮尾；大小按 WtDamage 的乘员盒子缩放，上下夹在车体底板和车顶 / 炮塔顶之间（不穿出车体）
--   · 弹药：一发一发的弹（弹体 + 弹头两种颜色；脱壳穿甲弹的弹头细长、破甲 / 榴弹的粗），发数按这辆车现在的弹（客户端 vs.ammo、
--     车上的 Rdy / RdyCap / AmL），打一发少一发，拿不到按满架画。转盘自动装弹机（WtDamage.CAROUSEL）画炮塔底下一圈：
--     T-72 / 90 / 96 / 99A 弹丸、药筒上下两层平躺，T-64 / T-80（篮子式）弹丸平躺、药筒竖着围在外圈；分装弹的车体弹架一格弹丸一格药筒；
--     机关炮、机枪画弹箱，榴弹炮画一发发弹丸，导弹 / 火箭画发射筒
--   · 发动机：柴油机 = 曲轴箱 + V 形两排气缸 + 缸盖罩 + 排气歧管和每缸的支管 + 增压器 + 顶上两个风扇 + 两侧散热器（T-64 / 72 / 90 / 96 / 99A 横置）；
--     燃气轮机（VehDefs turbine：M1、T-80）= 圆柱形的进气机匣、压气机、涡轮、回热器 + 排气道、空滤
--   · 传动：变速箱 + 两头转向机 + 通到主动轮的两根半轴 + 侧减速器（轮式车：传动轴 + 每根车桥）；油箱：圆角油箱（又宽又扁的画成鞍形）
--   · 炮：炮闩（摇架、耳轴、两根后坐筒、炮尾、闩体、防危板）、炮管（粗细两段、隔热套的箍、抽烟装置 / 炮口制退器的鼓包，画到炮口）、
--     并列机枪——跟着炮塔方位和炮的俯仰（用 View 的车体 / 炮塔 / 炮框架，俯仰、后坐都跟原模型对得上；没有 View 按 st.ty / st.gp 算）
--   · 炮塔驱动（座圈齿圈 + 电机 + 减速箱 + 小齿轮）、观瞄（炮长镜的镜头、窗口、镜筒一直到炮长眼前；车长周视镜、M1 的车长热像仪）、
--     履带（负重轮、主动轮、诱导轮、上下履带）/ 车轮、载员舱（两条长凳 + 坐着的步兵）；爆反块照旧用模型上真的块（VehModels 的 M.era）
--   · 状态（服务器写在车上的 WtC / WtM / WtF / WtAF，同战后 X 光回放）：完好按类别色；受损琥珀、打坏红、乘员阵亡深色；
--     起火一闪一闪的火光色（WtF：发动机、油箱；WtAF：弹药架）
--   · 屏幕：下面一排图例（这辆车有的类别 + 状态）；鼠标指着哪个部件，旁边写它的名字、状态（弹药架写还剩几发、指着的是哪种弹）
--   · 性能：零件对象池（松手收回、下次按住直接拿来用）；只在按住 X 时建、松手全清（零件收回、Highlight / 图例删掉、车身透明度还原）；
--     每帧只算 CFrame、一次 BulkMoveTo；Highlight 按类别分组（二十来个，Roblox 上限 31）；一辆车最多 600 个零件（弹多的车一发弹一个零件）
--   11-27 审查后补的：按住 X 时 Drive 放开鼠标、画出指针（镜头、炮塔这段时间不跟鼠标转），指哪个部件写哪个（原来鼠标锁在屏幕中间、只指得到炮管）；
--     手机上按住「透视」键，另一只手指点一下部件；车长坐到指挥塔正下方，头够不着指挥塔就不抬（不从炮塔顶冒出去）；转盘车的乘员踩在转盘的弹上面、
--     篮子式的竖药筒围在人脚外圈；乘员状态按座位（换了座的跟着人走）；AmL 变了按现在的弹重排弹名、弹头；加特林画转膛机匣；BMP / 布雷德利的反坦克导弹发射架；
--     车辆热成像（Night.lua 的 1 + 24 个 Highlight）按住 X 时让开；每帧在 init.client.lua 的 steps 里 View 之后摆（G.stepOwnXray，不晚一帧）
--   共用（XrayOwn.crewSpecs）：WtHud 的战后 X 光回放也用这套人形画乘员
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local XrayOwn = {}

local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local PI, RAD = math.pi, math.rad
local MS = 2.8      -- 1 米 = 2.8 格
local LIMIT = 600   -- 一辆车的透视零件上限
local MAXG = 28     -- 透视最多建几组 Highlight（Roblox 一个画面最多 31 个，车身轮廓线占一个）
XrayOwn.LIMIT, XrayOwn.MAXG = LIMIT, MAXG
-- 篮子式自动装弹机（T-64 / T-80）：弹丸平躺、药筒竖着围在外圈；别的转盘车（T-72 / 90 / 96 / 99A）弹丸、药筒上下两层平躺
local MZ = { t64a = true, t64b = true, t80b = true, t80u = true, t80bvm = true }
-- 转盘里的弹（格）：弹径（125 毫米）、离转盘底板多高开始放、竖药筒多高（篮子式）；乘员的地板、竖药筒围多大一圈也按这几个数算
local CAR_DIA, CAR_Y0, CAR_CH = 0.35, 0.1, 1.3
local CUP_R = 0.625   -- 车长指挥塔那一圈观察镜的半径（同下面画的那一圈：直径 1.25）
local CORNERS = {}   -- 方盒的八个角（± 半边长）
for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do CORNERS[#CORNERS + 1] = Vector3.new(sx, sy, sz) end end end
-- 自己一组 Highlight 的子件（颜色跟大类不一样、要一眼分得出的）：弹头、发动机的深色件（排气、风扇、缸盖）、炮闩 / 炮管的鼓包和箍、观瞄的玻璃
local SUBOK = { engine_dk = true, breech_dk = true, barrel_dk = true, ammo_tip = true, optics_gl = true }
XrayOwn.SUBOK = SUBOK

local mods = {}
local function req(name)
  local m = mods[name]
  if m == nil then
    m = require(RS:WaitForChild(name))
    mods[name] = m
  end
  return m
end
local function clampS(v, a, b)   -- 上下界可能倒过来（小车）：倒了取中间
  if a > b then return (a + b) / 2 end
  return math.clamp(v, a, b)
end

---------------------------------------------------------------- 形状（纯数据：零件大小、相对所在框架的 CFrame、形状、子组）

-- 一件：s 大小、cf 在框架里的位置、sh 形状（B 方块、S 球、C 圆柱——Roblox 的圆柱沿 X 轴）、g 子组（dk 深色件、tip 弹头、gl 玻璃）
local function put(L, size, cf, sh, g)
  local s = { s = V3(math.max(size.X, 0.04), math.max(size.Y, 0.04), math.max(size.Z, 0.04)), cf = cf, sh = sh or "B", g = g }
  L[#L + 1] = s
  return s
end
local function blk(L, size, pos, g, rot) return put(L, size, rot and (CF(pos) * rot) or CF(pos), "B", g) end
local function ball(L, dia, pos, g) return put(L, V3(dia, dia, dia), CF(pos), "S", g) end
local function upFor(dv) return (math.abs(dv.Y) > 0.7 * dv.Magnitude) and V3(0, 0, 1) or V3(0, 1, 0) end
-- 圆柱：从 a 到 b，直径 dia
local function rod(L, a, b, dia, g)
  local dv = b - a
  local len = dv.Magnitude
  if len < 0.02 then return nil end
  return put(L, V3(len, dia, dia), CFrame.lookAt((a + b) / 2, b, upFor(dv)) * ANG(0, PI / 2, 0), "C", g)
end
-- 方条：从 a 到 b，截面 w（横）× h（竖）
local function bar(L, a, b, w, h, g)
  local dv = b - a
  local len = dv.Magnitude
  if len < 0.02 then return nil end
  return put(L, V3(w, h, len), CFrame.lookAt((a + b) / 2, b, upFor(dv)), "B", g)
end
-- 轴朝上的圆盘
local function disc(L, pos, dia, h, g) return put(L, V3(h, dia, dia), CF(pos) * ANG(0, 0, PI / 2), "C", g) end
local function mark(L, n0, slot) for j = n0 + 1, #L do L[j].slot = slot end end

---------------------------------------------------------------- 人

-- 尺寸（米）：躯干（胯到脖子根）、脖子、头、肩宽、胯宽、上臂、前臂（带手）、大腿、小腿、脚
local BONE = { torso = 0.5, neck = 0.07, head = 0.23, sh = 0.4, hip = 0.28, uarm = 0.3, farm = 0.33, thigh = 0.45, shin = 0.44, foot = 0.24 }
local function U(x, y, z) return V3(x, y, z).Unit end
-- 各角色的姿势：各段朝哪（人自己的坐标：x 右、y 上、−z 朝前；左边那只按 x 镜像，带 R 的是右边单给的）；seat 胯离乘员盒子底多高（格）
local POSE = {
  -- 驾驶员：靠背往后倒四十来度、半躺着，膝盖抬起、脚往前伸到踏板，两手往前握操纵杆
  drv = { spine = U(0, 0.78, 0.62), head = U(0, 0.94, 0.34), uarm = U(0.16, -0.5, -0.85), farm = U(-0.1, 0.22, -0.97),
    thigh = U(0, 0.2, -0.98), shin = U(0, -0.56, -0.83), foot = U(0, 0.35, -0.94), seat = 0.55 },
  -- 炮长：坐着、身子往前探、低着头把脸贴在瞄准镜目镜上，两手握着操纵台
  gnr = { spine = U(0, 0.94, -0.34), head = U(0, 0.8, -0.6), uarm = U(0.12, -0.45, -0.88), farm = U(-0.06, 0.4, -0.92),
    thigh = U(0, -0.05, -1), shin = U(0, -0.96, -0.27), foot = U(0, -0.12, -0.99), seat = 0.42 },
  -- 车长：坐得高（座椅升起来），身子直、头伸进指挥塔；右手往上扶着周视镜的手柄
  cmd = { spine = U(0, 1, 0.03), head = U(0, 1, -0.05), uarm = U(0.22, -0.4, -0.89), farm = U(-0.12, 0.42, -0.9),
    uarmR = U(0.18, 0.55, -0.82), farmR = U(-0.08, 0.5, -0.86), thigh = U(0, -0.32, -0.95), shin = U(0, -1, 0.1), foot = U(0, -0.1, -0.99), high = true },
  -- 装填手：站着、身子稍往前，两手在腰前（捧着一发弹装进炮尾的样子）
  ldr = { spine = U(0, 0.99, -0.15), head = U(0, 0.97, -0.25), uarm = U(0.08, -0.82, -0.57), farm = U(-0.2, 0.22, -0.95),
    thigh = U(0, -1, -0.05), shin = U(0, -1, 0.04), foot = U(0, -0.04, -1), stand = true },
  -- 载员舱里坐着的步兵（简化：头、躯干、并拢的大腿、小腿）
  troop = { spine = U(0, 1, 0.08), head = U(0, 1, -0.02), uarm = U(0.08, -0.92, -0.38), farm = U(0, -0.15, -0.99),
    thigh = U(0, -0.04, -1), shin = U(0, -1, 0.06), foot = U(0, -0.05, -1), seat = 0.5 },
}
XrayOwn.POSE = POSE
-- 一个人：返回零件表（相对胯中心）、最低点、最高点（头顶或举起来的手，都相对胯）、头的中心、最靠前的一点（z）
--   lean：上身往哪边歪（水平的一个小向量，加到躯干、头的方向上；腿不动）——车长胯往里挪、头还凑在指挥塔底下
local function person(pose, sc, simple, lean)
  local L = {}
  local k = MS * sc
  local sp, hd = pose.spine, pose.head
  if lean then sp, hd = (sp + lean).Unit, (hd + lean).Unit end
  local N = sp * (BONE.torso * k)   -- 脖子根
  local headC = N + hd * ((BONE.neck + BONE.head / 2) * k)
  local lowY, minZ, hiY = -0.05 * k, 0, headC.Y + BONE.head / 2 * k
  local function see(p)
    if p.Y < lowY then lowY = p.Y end
    if p.Z < minZ then minZ = p.Z end
    if p.Y + 0.05 * k > hiY then hiY = p.Y + 0.05 * k end
  end
  ball(L, BONE.head * k, headC)
  bar(L, sp * (0.1 * k), N, 0.36 * k, 0.21 * k)                                       -- 躯干
  if not simple then bar(L, sp * (-0.07 * k), sp * (0.13 * k), 0.32 * k, 0.22 * k) end   -- 骨盆
  for side = -1, 1, 2 do
    local function m(v) return V3(v.X * side, v.Y, v.Z) end
    local Sh = N - sp * (0.06 * k) + V3(side * BONE.sh / 2 * k, 0, 0)
    local El = Sh + m((side > 0 and pose.uarmR) or pose.uarm) * (BONE.uarm * k)
    local Hd = El + m((side > 0 and pose.farmR) or pose.farm) * (BONE.farm * k)
    local Hp = V3(side * BONE.hip / 2 * k, -0.03 * k, 0)
    local Kn = Hp + m(pose.thigh) * (BONE.thigh * k)
    local An = Kn + m(pose.shin) * (BONE.shin * k)
    local To = An + m(pose.foot) * (BONE.foot * k)
    see(Hd) see(Kn) see(An - V3(0, 0.07 * k, 0)) see(To - V3(0, 0.07 * k, 0))
    if not simple then
      bar(L, Sh, El, 0.1 * k, 0.1 * k)                                               -- 上臂
      bar(L, El, Hd, 0.085 * k, 0.085 * k)                                           -- 前臂（带手）
      bar(L, Hp, Kn, 0.15 * k, 0.15 * k)                                             -- 大腿
      bar(L, Kn, An, 0.11 * k, 0.11 * k)                                             -- 小腿
      bar(L, An - V3(0, 0.035 * k, 0), To - V3(0, 0.035 * k, 0), 0.1 * k, 0.08 * k)  -- 脚
    elseif side > 0 then
      bar(L, V3(0, Hp.Y, 0), V3(0, Kn.Y, Kn.Z), 0.32 * k, 0.15 * k)                 -- 两条大腿并成一块
      bar(L, V3(0, Kn.Y, Kn.Z), V3(0, An.Y, An.Z), 0.28 * k, 0.12 * k)               -- 小腿
    end
  end
  return L, lowY, hiY, headC, minZ
end

---------------------------------------------------------------- 车里的尺寸（底座系：底面中心、y 上、−z 朝前；炮塔系：相对炮塔转轴）

local function mkCtx(d, lay)
  local T = d.turret
  local ctx = { d = d, lay = lay, byK = {}, hH = lay.hH, ts = lay.ts, tp = (T and T.pivot) or V3(0, lay.hH, 0), fl = (d.clear or 1.2) + 0.25 }
  for _, it in ipairs(lay.list) do ctx.byK[it.k] = it end
  -- 炮塔顶（底座系）：转轴比车顶低的车（BMP-2、猎豹：转轴定在车体底板附近）按车顶往上算
  ctx.turTop = math.max(ctx.hH, ctx.tp.Y) + ctx.ts.Y
  -- 主动轮在变速箱那头（侧减速器、半轴也通到那儿）
  local rw = d.rw
  local tr = ctx.byK.trans
  ctx.xIn = d.W / 2 - d.W * 0.13
  ctx.ySp = rw and ((rw.y or rw.r) + rw.r * 0.55) or (d.wr or 1.2)
  local zSp = tr and ((tr.lo.Z + tr.hi.Z) / 2) or (d.L / 2 - 1)
  if rw then
    local z0, z1 = math.min(rw.z0, rw.z1), math.max(rw.z0, rw.z1)
    if zSp >= 0 then zSp = clampS(zSp, z1 + rw.r * 0.9, d.L / 2 - rw.r * 0.7)
    else zSp = clampS(zSp, -d.L / 2 + rw.r * 0.7, z0 - rw.r * 0.9) end
  end
  ctx.zSp = zSp
  -- 篮子式转盘的竖药筒最外能放到离转轴多远：两边履带里面（比 WtDamage 的弹药盒子宽一点，真车药筒贴着炮塔座圈）
  ctx.carRmax = ctx.xIn - math.abs(ctx.tp.X) - CAR_DIA / 2 - 0.05
  return ctx
end

---------------------------------------------------------------- 各件的样子

-- 乘员（返回炮长的头：炮长镜的目镜对着它）
local function crewItem(x, ctx)
  local it, d = x.it, ctx.d
  local role = it.role or it.k
  local pose = POSE[role] or POSE.gnr
  if not it.tur and role == "gnr" then pose = POSE.ldr end     -- 车体上的机枪手（悍马顶上的枪塔）：站着
  if not it.tur and role == "cmd" then pose = POSE.troop end   -- 车体里坐着的车长（轻型车副驾驶）：坐直
  local size = it.hi - it.lo
  local c = (it.lo + it.hi) / 2
  local sc0 = math.clamp(math.min(size.X / 1.7, size.Y / 2.7, size.Z / 1.7), 0.55, 1.3)
  -- 车长坐到指挥塔正下方（左右夹在「炮塔半宽 − 肩宽」以内，不探出炮塔侧壁）；头离指挥塔中心不超过它的半径才伸进指挥塔，
  --   不然顶到炮塔顶为止（原来只往指挥塔挪半格、头却抬到指挥塔的高度：T-64、T-80 的车长脑袋从指挥塔旁边的炮塔顶冒出去）
  --   指挥塔在另一边的（勒克莱尔、10 式：车长盒子在右、指挥塔在左）不挪，免得坐到炮长身上
  local cup = (role == "cmd" and it.tur and d.cupola) or nil
  local headXZ = nil
  if cup and (cup.X * c.X >= 0 or math.abs(cup.X - c.X) < 1.2) then
    local xm = math.max(0, ctx.ts.X / 2 - BONE.sh * MS * sc0)
    local zm = math.max(0, ctx.ts.Z / 2 - 0.6)
    headXZ = V3(math.clamp(cup.X, -xm, xm), 0, math.clamp(cup.Z, -zm, zm))
  end
  local function offCup(p) return cup and V3(p.X - cup.X, 0, p.Z - cup.Z).Magnitude or math.huge end
  local useCup = headXZ ~= nil and offCup(headXZ) <= CUP_R
  -- 转盘自动装弹机：炮塔里的人踩在转盘的弹上面（真车乘员踩着转盘的盖板）——T-72 / 90 / 96 / 99A 两层平躺的弹：弹药架的顶；
  --   T-64 / T-80 篮子式：平躺的弹丸那一层的顶，竖着的药筒那一层高度以下人离转轴不超过 limR（药筒围在人脚外圈，见 carouselRack）
  local am = ctx.byK.ammo
  local car = it.tur and req("WtDamage").CAROUSEL[d.id] and am and not am.tur
  local carFloor, limR, yLim = nil, nil, nil
  if car then
    carFloor = (MZ[d.id] and (am.lo.Y + CAR_Y0 + CAR_DIA + 0.06) or (am.hi.Y + 0.02)) - ctx.tp.Y + 0.03   -- 车体系的高度换到炮塔系
    if MZ[d.id] then
      limR = ctx.carRmax - CAR_DIA / 2 - 0.06
      yLim = am.lo.Y + CAR_Y0 + CAR_DIA * 1.55 + CAR_CH - ctx.tp.Y
    end
  end
  -- 摆一次：shift 胯往哪挪（炮塔系水平）、lean 上身歪多少、cupOn 头伸不伸进指挥塔
  local function fit(shift, lean, cupOn)
    local sc = sc0
    local floor, roof
    if it.tur then
      floor, roof = ctx.fl - ctx.tp.Y + 0.05, ctx.turTop - ctx.tp.Y - 0.08
      if carFloor then floor = math.max(floor, carFloor) end
      if cupOn then roof = math.max(roof + 0.08, cup.Y) + 0.45 end   -- 头伸进指挥塔
    else
      floor, roof = ctx.fl + 0.02, ctx.hH - 0.03
    end
    if it.hi.Y + 0.2 > roof then roof = it.hi.Y + 0.2 end   -- 站在车顶枪塔里的机枪手（悍马）
    roof = math.min(roof, d.H - (it.tur and ctx.tp.Y or 0) - 0.05)   -- 怎么都不高过整车
    if roof < floor + 1 then roof = floor + 1 end
    local L, low, top, headC, minZ = person(pose, sc, false, lean)
    if top - low > roof - floor then   -- 塞不下：整个人缩小
      sc = sc * (roof - floor) / (top - low)
      L, low, top, headC, minZ = person(pose, sc, false, lean)
    end
    local hipY
    if pose.stand then hipY = floor - low
    elseif pose.high then hipY = roof - 0.08 - top
    else hipY = it.lo.Y + (pose.seat or 0.5) * sc end
    hipY = clampS(hipY, floor - low, roof - top)
    local N = pose.spine * (BONE.torso * MS * sc)
    local hip = V3(c.X, hipY, c.Z - N.Z / 2) + shift   -- 躯干在盒子中间、腿往前伸
    if headXZ then   -- 车长：头在指挥塔正下方（胯往里挪了 shift、上身往回歪 lean：头还在那儿；歪不了那么多的头跟着往里）
      local h0 = N + pose.head * ((BONE.neck + BONE.head / 2) * MS * sc)
      hip = V3(headXZ.X - h0.X, hipY, headXZ.Z - h0.Z) + shift
    end
    if not it.tur then   -- 车体里的（驾驶员）：脚别伸出车头
      local front = -d.L / 2 + 0.45
      if hip.Z + minZ < front then hip = hip + V3(0, 0, front - (hip.Z + minZ)) end
    end
    local place = CF(hip)
    if role == "ldr" and d.gun and it.tur then   -- 装填手朝着炮尾
      local tgt = d.gun.pivot + V3(0, 0, 1.4)
      local dv = V3(tgt.X - hip.X, 0, tgt.Z - hip.Z)
      if dv.Magnitude > 0.3 then place = CFrame.lookAt(hip, hip + dv) end
    end
    for _, s in ipairs(L) do s.cf = place * s.cf end
    return { L = L, head = place * headC, sc = sc }
  end
  -- 竖药筒那一层高度以下离转轴最远的一点：超出 limR 多少、往哪边
  local function excess(L)
    local best, dir = -math.huge, V3(1, 0, 0)
    for _, s in ipairs(L) do
      local h = s.s / 2
      for _, k in ipairs(CORNERS) do
        local p = s.cf * (h * k)
        if p.Y < yLim then
          local r = math.sqrt(p.X * p.X + p.Z * p.Z)
          if r > best then best, dir = r, (r > 1e-3) and V3(p.X / r, 0, p.Z / r) or dir end
        end
      end
    end
    return best - limR, dir
  end
  local shift, lean = V3(), nil
  local r
  for _ = 1, 6 do
    r = fit(shift, lean, useCup)
    local again = false
    if limR then
      local exc, dir = excess(r.L)
      if exc > 0.005 then   -- 人脚伸进竖药筒那一圈：整个人往转轴挪；车长胯挪进来、上身往指挥塔那边歪（最多二十来度）
        shift = shift - dir * (exc + 0.03)
        if headXZ then
          local Lh = (BONE.torso + BONE.neck + BONE.head / 2) * MS * r.sc
          lean = -shift / Lh
          if lean.Magnitude > 0.36 then lean = lean.Unit * 0.36 end
        end
        again = true
      end
    end
    if not again and useCup and offCup(r.head) > CUP_R + 1e-3 then useCup, again = false, true end   -- 歪到头了头还够不着指挥塔：不抬
    if not again then break end
  end
  x.specs = r.L
  if role == "gnr" and it.tur then ctx.gnrHead = r.head end
end

-- 柴油机（本地坐标：盒子中心为原点，曲轴沿 z，+z 朝变速箱）
local function diesel(L, S)
  local w, h, l = S.X, S.Y, S.Z
  local y0 = -h / 2
  blk(L, V3(w * 0.5, h * 0.36, l * 0.8), V3(0, y0 + h * 0.27, 0))                    -- 曲轴箱
  blk(L, V3(w * 0.36, h * 0.1, l * 0.62), V3(0, y0 + h * 0.05, 0), "dk")             -- 油底壳
  for s = -1, 1, 2 do
    local tilt = ANG(0, 0, -s * RAD(30))
    local up = V3(s * 0.5, 0.866, 0)
    local bc = V3(s * w * 0.16, y0 + h * 0.57, 0)
    put(L, V3(w * 0.21, h * 0.34, l * 0.74), CF(bc) * tilt)                          -- 一排气缸（V 形，各往外倒 30°）
    put(L, V3(w * 0.18, h * 0.07, l * 0.7), CF(bc + up * (h * 0.205)) * tilt, "B", "dk")   -- 缸盖罩
    local xm, ym = s * w * 0.4, y0 + h * 0.5
    rod(L, V3(xm, ym, -l * 0.37), V3(xm, ym, l * 0.36), h * 0.11, "dk")              -- 排气歧管
    for i = 1, 6 do                                                                 -- 每缸一根排气支管
      local z = -l * 0.31 + (i - 1) / 5 * l * 0.62
      rod(L, bc + V3(s * w * 0.1, -h * 0.02, z), V3(xm, ym, z), h * 0.065, "dk")
    end
    rod(L, V3(s * w * 0.32, y0 + h * 0.8, -l * 0.36), V3(s * w * 0.44, y0 + h * 0.8, -l * 0.36), h * 0.2, "dk")   -- 涡轮增压器
    blk(L, V3(w * 0.06, h * 0.38, l * 0.46), V3(s * w * 0.47, y0 + h * 0.75, l * 0.18))   -- 散热器
    local fc = V3(s * w * 0.24, y0 + h * 0.94, l * 0.18)                             -- 风扇（顶上，冷却风从发动机盖进出）
    local fd = math.min(w * 0.4, l * 0.42)
    disc(L, fc, fd, h * 0.05)
    bar(L, fc + V3(-fd * 0.45, h * 0.035, 0), fc + V3(fd * 0.45, h * 0.035, 0), fd * 0.12, h * 0.02, "dk")   -- 扇叶
    bar(L, fc + V3(0, h * 0.035, -fd * 0.45), fc + V3(0, h * 0.035, fd * 0.45), fd * 0.12, h * 0.02, "dk")
  end
  blk(L, V3(w * 0.1, h * 0.12, l * 0.66), V3(0, y0 + h * 0.7, 0))                    -- 进气管（两排中间）
  rod(L, V3(0, y0 + h * 0.3, l * 0.4), V3(0, y0 + h * 0.3, l * 0.5), h * 0.52, "dk")   -- 飞轮壳（接变速箱）
end
-- 燃气轮机（本地坐标同上）：圆柱形的机身沿 z 躺着，前面进气、后面回热器最粗
local function turbine(L, S)
  local w, h, l = S.X, S.Y, S.Z
  local y0 = -h / 2
  local yc = y0 + h * 0.44
  local D = math.min(w * 0.55, h * 0.7)
  rod(L, V3(0, yc, -l * 0.44), V3(0, yc, -l * 0.27), D * 1.1)                        -- 进气机匣
  rod(L, V3(0, yc, -l * 0.27), V3(0, yc, l * 0.06), D * 0.9)                         -- 压气机、燃烧室
  rod(L, V3(0, yc, l * 0.06), V3(0, yc, l * 0.16), D, "dk")                          -- 涡轮
  rod(L, V3(0, yc, l * 0.16), V3(0, yc, l * 0.42), D * 1.22)                         -- 回热器
  for _, f in ipairs({ -0.2, -0.1, 0, 0.26, 0.34 }) do                               -- 机匣上一道道的环
    rod(L, V3(0, yc, l * f - 0.05), V3(0, yc, l * f + 0.05), D * ((f > 0.15) and 1.26 or 0.95), "dk")
  end
  blk(L, V3(w * 0.44, h * 0.3, l * 0.14), V3(0, y0 + h * 0.84, l * 0.36), "dk")      -- 排气道（往上通到发动机盖的百叶窗）
  blk(L, V3(w * 0.3, h * 0.24, l * 0.16), V3(0, y0 + h * 0.12, -l * 0.3))            -- 附件齿轮箱
  blk(L, V3(w * 0.34, h * 0.32, l * 0.1), V3(0, y0 + h * 0.2, l * 0.46))             -- 减速器（接变速箱）
  for s = -1, 1, 2 do
    blk(L, V3(w * 0.22, h * 0.36, l * 0.36), V3(s * w * 0.37, y0 + h * 0.72, -l * 0.22))   -- 空滤
    rod(L, V3(s * w * 0.25, yc, -l * 0.1), V3(s * w * 0.37, y0 + h * 0.6, -l * 0.18), h * 0.12)   -- 空滤出来的进气管
    local fc = V3(s * w * 0.3, y0 + h * 0.94, l * 0.2)
    local fd = math.min(w * 0.3, l * 0.3)
    disc(L, fc, fd, h * 0.05)                                                        -- 机油散热器的风扇
    bar(L, fc + V3(-fd * 0.45, h * 0.035, 0), fc + V3(fd * 0.45, h * 0.035, 0), fd * 0.12, h * 0.02, "dk")
  end
end
local function engineItem(x, ctx)
  local it, d = x.it, ctx.d
  local lo, hi = it.lo, it.hi
  local S, c = hi - lo, (lo + hi) / 2
  local tr = ctx.byK.trans
  local tz = tr and ((tr.lo.Z + tr.hi.Z) / 2) or (c.Z + 1)
  local W = req("WtDamage")
  local frame, sz
  if W.CAROUSEL[d.id] and not d.turbine then   -- 苏 / 俄 / 中国的 V 型柴油机横着放
    frame, sz = CF(c) * ANG(0, PI / 2, 0), V3(S.Z, S.Y, S.X)
  else
    frame, sz = CF(c) * ((tz >= c.Z) and CF() or ANG(0, PI, 0)), S
  end
  local L = {}
  if d.turbine then turbine(L, sz) else diesel(L, sz) end
  for _, s in ipairs(L) do s.cf = frame * s.cf end
  x.specs = L
  x.detail = d.turbine and "xr.d.turbine" or "xr.d.diesel"
end

local function transItem(x, ctx)
  local it, d = x.it, ctx.d
  local lo, hi = it.lo, it.hi
  local S, c = hi - lo, (lo + hi) / 2
  local L = {}
  blk(L, V3(S.X * 0.4, S.Y * 0.8, S.Z * 0.8), c)                                     -- 变速箱
  if d.arch == "wheeled" and d.axles and #d.axles > 0 then
    local wr = d.wr or 1.3
    local zs = {}
    for _, z in ipairs(d.axles) do zs[#zs + 1] = z end
    table.sort(zs)
    local far = (math.abs(zs[1] - c.Z) > math.abs(zs[#zs] - c.Z)) and zs[1] or zs[#zs]
    rod(L, V3(c.X, c.Y - S.Y * 0.2, c.Z), V3(0, wr + 0.1, far), math.max(0.16, S.Y * 0.16))   -- 传动轴
    local wx = (d.wx or d.W * 0.38) - (d.ww or 1) / 2
    for _, z in ipairs(zs) do
      ball(L, math.min(0.8, S.Y * 0.7), V3(0, wr, z), "dk")                          -- 差速器
      rod(L, V3(-wx, wr, z), V3(wx, wr, z), 0.24)                                    -- 车桥
    end
  else
    for s = -1, 1, 2 do
      rod(L, c + V3(s * S.X * 0.2, 0, 0), c + V3(s * S.X * 0.28, 0, 0), S.Y * 0.88, "dk")   -- 两头的转向机
      local fd = V3(s * (ctx.xIn - 0.2), ctx.ySp, ctx.zSp)
      rod(L, c + V3(s * S.X * 0.28, 0, 0), fd, math.max(0.16, S.Y * 0.2))            -- 半轴（通到主动轮）
      rod(L, fd - V3(s * 0.18, 0, 0), fd + V3(s * 0.22, 0, 0), S.Y * 0.78, "dk")      -- 侧减速器
    end
  end
  x.specs = L
end

-- 履带（负重轮、主动轮、诱导轮、上下履带）/ 车轮
local function trackItem(x, ctx)
  local it, d = x.it, ctx.d
  local lo, hi = it.lo, it.hi
  local side = (it.k == "trackL") and -1 or 1
  local L = {}
  local rw = d.rw
  if d.arch == "tracked" and rw and (rw.n or 0) > 0 then
    local xc = side * (rw.x or math.abs((lo.X + hi.X) / 2))   -- 负重轮那一列（VehDefs 照模型量的）
    local tw = (hi.X - lo.X) * 0.82
    local x0, x1 = xc - tw / 2, xc + tw / 2
    local n, r = rw.n, rw.r
    local y = rw.y or r
    for i = 1, n do
      local z = rw.z0 + ((n > 1) and ((i - 1) / (n - 1)) or 0.5) * (rw.z1 - rw.z0)
      rod(L, V3(x0, y, z), V3(x1, y, z), r * 1.8)                                    -- 负重轮
    end
    local z0, z1 = math.min(rw.z0, rw.z1), math.max(rw.z0, rw.z1)
    local zS = ctx.zSp
    local zI = (zS >= 0) and clampS(z0 - r * 1.6, lo.Z + r, z0 - r) or clampS(z1 + r * 1.6, z1 + r, hi.Z - r)
    local yS, yI, rS, rI = y + r * 0.55, y + r * 0.35, r * 0.85, r * 0.75
    rod(L, V3(x0, yS, zS), V3(x1, yS, zS), rS * 2)                                   -- 主动轮
    rod(L, V3(x0, yI, zI), V3(x1, yI, zI), rI * 2)                                   -- 诱导轮
    local zF, yF, rF, zR, yR, rR = zI, yI, rI, zS, yS, rS
    if zS < zI then zF, yF, rF, zR, yR, rR = zS, yS, rS, zI, yI, rI end
    local t = 0.13
    local zA, zB = z0 - r * 0.2, z1 + r * 0.2
    local topY = math.max(yF + rF, yR + rR, y + r + 0.08) + t / 2
    bar(L, V3(xc, t / 2, zA), V3(xc, t / 2, zB), tw, t)                              -- 下面一段（着地）
    bar(L, V3(xc, topY, zF), V3(xc, topY, zR), tw, t)                                -- 上面一段
    bar(L, V3(xc, yF, zF - rF), V3(xc, t / 2, zA), tw, t)                            -- 前头绕下来
    bar(L, V3(xc, yR, zR + rR), V3(xc, t / 2, zB), tw, t)                            -- 后头绕下来
  elseif d.axles and #d.axles > 0 then
    local wr, ww = d.wr or 1.3, d.ww or 1
    local wx = side * (d.wx or d.W * 0.38)
    for _, z in ipairs(d.axles) do
      rod(L, V3(wx - ww / 2, wr, z), V3(wx + ww / 2, wr, z), wr * 2)                 -- 轮胎
      rod(L, V3(wx - ww / 2 - 0.04, wr, z), V3(wx + ww / 2 + 0.04, wr, z), wr * 0.9)   -- 轮毂
    end
  else
    blk(L, hi - lo, (lo + hi) / 2)
  end
  x.specs = L
end

-- 油箱：圆角油箱（四条圆柱边沿长的那根轴）；又宽又扁的画成鞍形（两边两块、上面一道梁）
local function fuelItem(x)
  local it = x.it
  local S = it.hi - it.lo - V3(0.1, 0.1, 0.1)
  local c = (it.lo + it.hi) / 2
  local L = {}
  local rotZ = S.X > S.Z * 1.25   -- 长边沿 x：整个转 90°
  local frame = rotZ and (CF(c) * ANG(0, PI / 2, 0)) or CF(c)
  local w, h, l = S.X, S.Y, S.Z
  if rotZ then w, l = S.Z, S.X end
  if w > h * 1.5 and w > 2.2 then
    for s = -1, 1, 2 do
      blk(L, V3(w * 0.3, h, l), V3(s * w * 0.35, 0, 0))                              -- 鞍形两边
      rod(L, V3(s * w * 0.35, h * 0.34, -l / 2), V3(s * w * 0.35, h * 0.34, l / 2), math.min(w * 0.3, h * 0.32))
    end
    blk(L, V3(w * 0.42, h * 0.34, l), V3(0, h * 0.33, 0))                            -- 上面的梁
  else
    local r = math.min(w, h) * 0.22
    blk(L, V3(w - 2 * r, h, l), V3())
    blk(L, V3(w, h - 2 * r, l), V3())
    for sx = -1, 1, 2 do
      for sy = -1, 1, 2 do
        rod(L, V3(sx * (w / 2 - r), sy * (h / 2 - r), -l / 2), V3(sx * (w / 2 - r), sy * (h / 2 - r), l / 2), 2 * r)   -- 圆角
      end
    end
  end
  disc(L, V3(w * 0.22, h / 2 + 0.05, -l * 0.28), math.min(0.36, w * 0.25), 0.14, "dk")   -- 加油口
  for _, s in ipairs(L) do s.cf = frame * s.cf end
  x.specs = L
end

-- 炮闩（炮的坐标：耳轴为原点、−z 朝炮口）
local function breechItem(x, ctx)
  local d = ctx.d
  local g = d.gun
  local L = {}
  local cal = math.max(0.1, g.cal or 0.3)
  local hiZ = x.it.hi.Z - g.pivot.Z
  local twin = d.turret and d.turret.twin
  local xs = twin and { -twin / 2, twin / 2 } or { 0 }
  for _, x0 in ipairs(xs) do
    if g.gatling then   -- 加特林（M163、LD-2000、C-RAM 的 M61 / 730 型）：炮管后面一个圆柱形的转膛机匣 + 侧面的驱动电机 + 往下通到弹鼓的无链供弹槽
      rod(L, V3(x0, 0, -0.3), V3(x0, 0, 1.3), cal * 2.3)                                -- 转膛机匣（六根管的后头都在里面）
      rod(L, V3(x0, 0, -0.42), V3(x0, 0, -0.3), cal * 2.5, "dk")                        -- 前面的夹箍
      blk(L, V3(cal * 1.1, cal * 1.1, 0.7), V3(x0 + cal * 1.6, cal * 0.2, 0.6), "dk")   -- 驱动电机（液压 / 电动）
      blk(L, V3(cal * 2.2, cal * 0.5, 1.4), V3(x0, -cal * 1.35, 0.55))                  -- 炮架
      bar(L, V3(x0 - cal * 0.9, -cal * 0.9, 1.0), V3(x0 - 0.7, -1.3, 1.5), 0.32, 0.14, "dk")   -- 供弹槽（往下通到弹鼓）
      bar(L, V3(x0 - cal * 0.5, -cal * 1.0, 1.2), V3(x0 - 0.35, -1.3, 1.9), 0.32, 0.14, "dk")  -- 退弹槽（空弹壳回弹鼓）
    elseif cal < 0.3 or (g.len or 0) < 1 then   -- 机关炮 / 发射架：机匣 + 供弹槽
      local k = math.clamp(cal / 0.2, 0.6, 1.4)
      blk(L, V3(0.5 * k, 0.42 * k, 1.5), V3(x0, 0, 0.55))
      rod(L, V3(x0, 0, -0.35), V3(x0, 0, 0.1), 0.34 * k, "dk")                        -- 驻退套
      bar(L, V3(x0 - 0.18 * k, -0.15 * k, 0.6), V3(x0 - 0.5 * k, -1.1, 0.9), 0.3 * k, 0.12, "dk")   -- 供弹槽（往下通到弹箱）
    else
      local k = math.clamp(cal / 0.44, 0.4, 1.3)
      blk(L, V3(0.95 * k, 0.85 * k, 0.9), V3(x0, 0, -0.05))                           -- 摇架
      rod(L, V3(x0 - 0.62 * k, 0, 0), V3(x0 + 0.62 * k, 0, 0), 0.22 * k, "dk")        -- 耳轴
      for s = -1, 1, 2 do
        rod(L, V3(x0 + s * 0.3 * k, 0.36 * k, -0.4), V3(x0 + s * 0.3 * k, 0.36 * k, 0.95), 0.2 * k, "dk")   -- 两根后坐筒（驻退机、复进机）
      end
      local zr = 0.45 + 0.35 * k
      blk(L, V3(1.0 * k, 0.95 * k, 0.7 * k), V3(x0, -0.02, zr))                       -- 炮尾
      blk(L, V3(0.22 * k, 0.78 * k, 0.52 * k), V3(x0 + 0.42 * k, -0.02, zr), "dk")    -- 立楔式闩体（往右探出来一点）
      local z1 = zr + 0.35 * k
      local z2 = math.max(z1 + 0.3, math.min(hiZ - 0.05, z1 + 1.2))
      for s = -1, 1, 2 do blk(L, V3(0.06, 0.55 * k, z2 - z1), V3(x0 + s * 0.56 * k, 0, (z1 + z2) / 2)) end   -- 防危板（后坐时挡着人）
      blk(L, V3(1.12 * k, 0.06, z2 - z1), V3(x0, -0.32 * k, (z1 + z2) / 2))           -- 接壳托
    end
  end
  x.specs = L
end
-- 炮管（炮的坐标）：粗细两段、隔热套的箍、抽烟装置 / 炮口制退器，一直画到炮口
local function barrelItem(x, ctx)
  local g = ctx.d.gun
  local L = {}
  local len, cal = g.len or 0, g.cal or 0
  if len < 1 or cal <= 0 then   -- 发射架：一根导轨
    local l = math.max(1.5, len)
    blk(L, V3(0.3, 0.2, l), V3(0, 0, -l / 2))
    x.specs = L
    return
  end
  local twin = ctx.d.turret and ctx.d.turret.twin
  local xs = twin and { -twin / 2, twin / 2 } or { 0 }
  for _, x0 in ipairs(xs) do
    if g.gatling then   -- 加特林：六根管围一圈 + 两道夹箍
      for i = 0, 5 do
        local a = i / 6 * PI * 2
        local ox, oy = math.cos(a) * cal * 0.55, math.sin(a) * cal * 0.55
        rod(L, V3(x0 + ox, oy, -0.3), V3(x0 + ox, oy, -len), cal * 0.42)
      end
      rod(L, V3(x0, 0, -len * 0.7 + 0.06), V3(x0, 0, -len * 0.7 - 0.06), cal * 1.7, "dk")
      rod(L, V3(x0, 0, -len + 0.12), V3(x0, 0, -len - 0.02), cal * 1.75, "dk")
    else
      local zM = -0.35 - (len - 0.35) * 0.45
      rod(L, V3(x0, 0, -0.35), V3(x0, 0, zM), cal * 1.62)                             -- 后段（粗）
      rod(L, V3(x0, 0, zM), V3(x0, 0, -len), cal * 1.28)                              -- 前段（细）
      for _, f in ipairs({ 0.3, 0.8 }) do
        rod(L, V3(x0, 0, -len * f + 0.07), V3(x0, 0, -len * f - 0.07), cal * 1.8, "dk")   -- 隔热套的箍
      end
      if g.fume then rod(L, V3(x0, 0, -len * 0.52), V3(x0, 0, -len * 0.64), cal * 2.15, "dk") end   -- 抽烟装置
      if g.brake then
        rod(L, V3(x0, 0, -len * 0.925), V3(x0, 0, -len - 0.02), cal * 2, "dk")        -- 炮口制退器
        blk(L, V3(cal * 2.6, cal * 0.8, len * 0.035), V3(x0, 0, -len * 0.965), "dk")  -- 两侧的开窗
      end
    end
  end
  x.specs = L
end

-- 炮塔驱动（炮塔系）：座圈一圈齿圈 + 电机 + 减速箱 + 跟齿圈咬着的小齿轮
local function tdriveItem(x, ctx)
  local it, d = x.it, ctx.d
  local lo, hi = it.lo, it.hi
  local c = (lo + hi) / 2
  local L = {}
  local R = clampS(math.min(ctx.ts.X, ctx.ts.Z) * 0.36, 1.2, d.W * 0.36)
  local yr = clampS(ctx.hH - ctx.tp.Y - 0.12, lo.Y - 0.3, hi.Y + 0.3)
  local N = 14
  for i = 0, N - 1 do
    local a0, a1 = i / N * PI * 2, (i + 1) / N * PI * 2
    bar(L, V3(math.sin(a0) * R, yr, math.cos(a0) * R), V3(math.sin(a1) * R, yr, math.cos(a1) * R), 0.18, 0.14)   -- 座圈齿圈
  end
  disc(L, c + V3(0, 0.12, 0), 0.56, 0.62)                                            -- 电机
  blk(L, V3(0.5, 0.34, 0.5), c + V3(0, -0.36, 0))                                    -- 减速箱
  local u = V3(c.X, 0, c.Z)
  u = (u.Magnitude > 0.1) and u.Unit or V3(-0.7, 0, -0.7)
  disc(L, V3(u.X * (R - 0.18), yr, u.Z * (R - 0.18)), 0.34, 0.2)                     -- 小齿轮
  x.specs = L
end

-- 炮长瞄准镜（炮塔系）：镜头（装甲罩 + 窗口）、镜筒穿过炮塔顶一直到炮长眼前、目镜
local function opticsItem(x, ctx)
  local d = ctx.d
  local sp = d.sight or (x.it.lo + x.it.hi) / 2
  local L = {}
  blk(L, V3(1.0, 0.62, 0.9), sp + V3(0, 0.14, 0))
  blk(L, V3(0.72, 0.3, 0.06), sp + V3(0, 0.18, -0.47), "gl")
  local eye = ctx.gnrHead and (ctx.gnrHead + V3(0, 0.02, -0.34)) or (sp + V3(0, -1.1, 0.5))
  bar(L, sp + V3(0, -0.12, 0.1), eye + V3(0, 0.06, -0.12), 0.34, 0.34)
  rod(L, eye, eye + V3(0, 0, 0.2), 0.24, "gl")
  x.specs = L
end

-- 载员舱：两条长凳 + 面朝里坐着的步兵
local function troopsItem(x, ctx)
  local it, d = x.it, ctx.d
  local lo, hi = it.lo, it.hi
  local S, c = hi - lo, (lo + hi) / 2
  local L = {}
  local _, low0, top0 = person(POSE.troop, 1, true)
  local sc = math.clamp((ctx.hH - 0.08 - lo.Y) / (top0 - low0), 0.5, 1)
  local P0, low = person(POSE.troop, sc, true)
  local hipY = lo.Y - low + 0.02
  local benchX = math.max(0.3, S.X / 2 - 0.4)
  for s = -1, 1, 2 do blk(L, V3(0.6, 0.12, S.Z * 0.86), V3(c.X + s * benchX, hipY - 0.12 * sc, c.Z)) end   -- 长凳
  local n = math.clamp((d.seats or 6) - 1, 2, 6)
  local per = math.ceil(n / 2)
  for i = 1, n do
    local s = (i % 2 == 1) and -1 or 1
    local j = math.ceil(i / 2)
    local z = c.Z - S.Z * 0.4 + (j - 0.5) / per * S.Z * 0.8
    local hip = V3(c.X + s * (benchX - 0.05), hipY, z)
    local place = CFrame.lookAt(hip, hip + V3(-s, 0, 0))   -- 面朝里
    for _, q in ipairs(P0) do L[#L + 1] = { s = q.s, cf = place * q.cf, sh = q.sh } end
  end
  x.specs = L
end

---------------------------------------------------------------- 弹

-- 弹头占多长、多粗（按弹种类 cls）：脱壳穿甲弹细长的弹芯；破甲、榴弹粗；榴弹炮弹丸的引信、火箭、导弹的头
local function shellShape(cls)
  if cls == "ap" then return 0.46, 0.5 end
  if cls == "heat" or cls == "mpat" or cls == "jet" then return 0.42, 0.86 end
  if cls == "atgm" then return 0.55, 0.9 end
  if cls == "shell" then return 0.24, 0.5 end
  if cls == "rocket" then return 0.18, 0.72 end
  if cls == "msl" then return 0.2, 0.85 end
  return 0.4, 0.8
end
-- 一发躺着的整装弹（沿 dir，弹头朝 dir）
local function round(L, c, dir, dia, len, cls, one)
  local a, b = c - dir * (len / 2), c + dir * (len / 2)
  if one then rod(L, a, b, dia) return end
  local tf, tk = shellShape(cls)
  local m = b - dir * (len * tf)
  rod(L, a, m, dia)                    -- 药筒 / 弹体
  rod(L, m, b, dia * tk, "tip")        -- 弹头
end
-- 盒子里一格一格排的弹（沿 z 躺着，横截面排成几行几列；放不下的弹径缩小）：n 格；sep 分装弹（单数格弹丸、双数格药筒）
local function gridRack(L, lo, hi, n, dia0, len0, tipDir, kinds, one, sep)
  if n <= 0 then return end
  local S = hi - lo
  local w, h = math.max(0.2, S.X - 0.12), math.max(0.2, S.Y - 0.1)
  local rows = math.clamp(math.floor(math.sqrt(n * h / w) + 0.5), 1, math.max(1, math.floor(h / (dia0 * 0.6))))
  local cols = math.ceil(n / rows)
  local dia = math.min(dia0, w / cols * 0.94, h / rows * 0.94)
  local len = math.max(0.3, math.min(len0, S.Z - 0.12))
  local zc = (lo.Z + hi.Z) / 2
  local dir = V3(0, 0, tipDir)
  for i = 1, n do
    local row, col = math.floor((i - 1) / cols), (i - 1) % cols
    local p = V3(lo.X + 0.06 + (col + 0.5) * (w / cols), lo.Y + 0.05 + (row + 0.5) * (h / rows), zc)
    local n0 = #L
    if sep then
      local proj = (i % 2 == 1)
      local l2 = len * (proj and 0.72 or 0.62)
      rod(L, p - dir * (l2 / 2), p + dir * (l2 / 2), dia * (proj and 0.9 or 1), proj and "tip" or nil)
    else
      round(L, p, dir, dia, len, kinds and kinds[i], one)
    end
    mark(L, n0, i)
  end
end
-- 转盘自动装弹机（车体底板上、炮塔下面一圈）：n 个位置，弹头朝里；crewR 炮塔里的人脚伸到离转轴多远（篮子式的竖药筒围在它外面）、
--   rMax 竖药筒最外放到多远
local function carouselRack(L, lo, hi, n, mz, one, crewR, rMax)
  local c = (lo + hi) / 2
  local S = hi - lo
  local rOut = math.max(1.2, math.min(S.X, S.Z) / 2 - 0.12)
  local dia = CAR_DIA   -- 125 毫米
  local rIn = math.min(math.max(n * dia * 1.12 / (PI * 2), rOut * 0.3), rOut - 0.9)
  local len = rOut - rIn
  disc(L, V3(c.X, lo.Y + 0.04, c.Z), rOut * 2 + 0.1, 0.08)                          -- 转盘底板
  local y1 = lo.Y + CAR_Y0 + dia / 2
  local y2 = y1 + dia + 0.06
  -- 竖药筒那一圈：原来在弹丸外头那一截上面；炮塔里的人脚伸得远就往外挪（最多挪到履带里面）
  local rC = math.max(rOut - dia * 0.6, (crewR or 0) + dia / 2 + 0.06)
  if rMax then rC = math.min(rC, rMax) end
  for i = 1, n do
    local a = (i - 0.5) / n * PI * 2
    local u = V3(math.sin(a), 0, math.cos(a))
    local n0 = #L
    local pc = V3(c.X, y1, c.Z)
    rod(L, pc + u * rOut, pc + u * (rIn + len * 0.12), dia * 0.92, "tip")            -- 弹丸（下层平躺）
    if not one then
      if mz then
        local p = V3(c.X, 0, c.Z) + u * rC
        rod(L, V3(p.X, y1 + dia * 0.55, p.Z), V3(p.X, y1 + dia * 0.55 + CAR_CH, p.Z), dia)   -- 药筒（竖着围在外圈）
      else
        local qc = V3(c.X, y2, c.Z)
        rod(L, qc + u * rOut, qc + u * (rIn + len * 0.3), dia)                       -- 药筒（上层平躺）
      end
    end
    mark(L, n0, i)
  end
end
-- 机关炮 / 机枪的弹箱：n 箱（箱子 + 箱口露出的一截弹链）
local function canRack(L, lo, hi, n, one)
  if n <= 0 then return end
  local S = hi - lo
  local rows = math.clamp(math.ceil(n / math.max(1, math.floor(S.X / 0.62))), 1, math.max(1, math.floor(S.Y / 0.42)))
  local cols = math.ceil(n / rows)
  local cw, ch = S.X / cols, S.Y / rows
  local dz = math.min(S.Z * 0.85, 1.1)
  for i = 1, n do
    local row, col = math.floor((i - 1) / cols), (i - 1) % cols
    local p = V3(lo.X + (col + 0.5) * cw, lo.Y + (row + 0.5) * ch, (lo.Z + hi.Z) / 2)
    local n0 = #L
    blk(L, V3(cw * 0.86, ch * 0.8, dz), p)
    if not one then blk(L, V3(cw * 0.7, 0.06, dz * 0.9), p + V3(0, ch * 0.4 + 0.03, 0), "tip") end
    mark(L, n0, i)
  end
end

-- 这辆车的主武器（画弹架用的那一件）
function XrayOwn.mainWeapon(d)
  local VD = req("VehDefs")
  for _, id in ipairs(d.weapons or {}) do
    local w = VD.W[id]
    if w and (w.kind == "shell" or w.kind == "arty" or w.kind == "atgm" or w.kind == "sam" or w.kind == "gun") then return id, w end
  end
  return nil, nil
end
-- 弹的样子、弹种顺序（live：{ total 主武器还有几发、rdy / rdyCap 待发弹架、aml 每种几发 }；没有就按满架）
function XrayOwn.ammoPlan(d, live)
  live = live or {}
  local A = { style = "none" }
  local wid, w = XrayOwn.mainWeapon(d)
  if not w then return A end
  A.wid, A.w = wid, w
  local cal = tonumber(string.match(wid, "^gun(%d+)")) or ((wid == "how155") and 155) or nil
  A.cal = cal
  if w.kind == "shell" and cal and cal >= 60 then
    A.style = "round"
    A.sep = (cal == 125)   -- 125 毫米：弹丸、药筒分装
    A.dia = (cal >= 115 and 0.44) or (cal >= 100 and 0.36) or (cal >= 90 and 0.34) or 0.26
    A.len = A.sep and 2.1 or ((cal >= 115 and 2.74) or (cal >= 100 and 2.7) or (cal >= 90 and 2.6) or 2.9)
    if cal >= 150 then A.dia, A.len = 0.46, 2.2 end
  elseif w.kind == "shell" or w.kind == "gun" then
    A.style, A.per = "cans", math.clamp(w.mag or 50, 20, 512)
  elseif w.kind == "arty" then
    A.style = "round"
    if wid == "mlrs" then A.dia, A.len, A.cls = 0.62, 3.6, "rocket" else A.dia, A.len, A.cls = 0.43, 2.24, "shell" end
  else
    A.style, A.dia, A.len, A.cls = "round", 0.5, 3.2, "msl"
  end
  A.full = (w.mag or 1) + (w.reserve or 0)
  -- 弹种顺序（AmL「m829a3:20,m830:12,…」）：画的时候一格一种
  local seq = {}
  if type(live.aml) == "string" then
    for k, c in string.gmatch(live.aml, "([%w_]+):(%d+)") do
      for _ = 1, math.min(tonumber(c) or 0, 400) do seq[#seq + 1] = k end
    end
  end
  local B = req("Ballistics")
  if #seq == 0 and B.GUN and B.GUN[wid] then seq[1] = B.GUN[wid][1] end
  A.seq = seq
  return A
end
-- 各弹架现在几发（rounds：cans 是几箱）、一共几格；每帧按车上的属性重算（打一发少一发）
function XrayOwn.racksOf(A, d, lay, live)
  live = live or {}
  local out = {}
  local w = A.w
  if not w then return out end
  local full = A.full
  local total = math.clamp(math.floor(tonumber(live.total) or full), 0, 9999)
  local lt = lay.prof.lay
  local hasH = false
  for _, it in ipairs(lay.list) do if it.k == "ammoH" then hasH = true end end
  if hasH and (lt == "e3" or lt == "w4") and A.style == "round" then
    local cap = math.floor(tonumber(live.rdyCap) or d.rdyN or ((lt == "e3") and 22 or 15))
    local mag = math.min(w.mag or 1, total)
    local res = total - mag
    local rdy = math.clamp(math.floor(tonumber(live.rdy) or math.min(cap, res)), 0, cap)
    local nH = math.max(0, res - rdy)
    out.ammo = { cap = cap, n = rdy }
    out.ammoH = { cap = math.max(full - (w.mag or 1) - cap, nH, 0), n = nH }
  elseif A.style == "cans" then
    out.ammo = { cap = math.clamp(math.ceil(full / A.per), 1, 12), n = math.clamp(math.ceil(total / A.per), 0, 12) }
  else
    out.ammo = { cap = full, n = total }
  end
  if hasH and not out.ammoH then out.ammoH = { cap = 0, n = 0 } end
  return out
end

local function ammoItem(x, ctx, one, scale)
  local it, d, A = x.it, ctx.d, ctx.A
  local rk = ctx.R[it.k] or { cap = 0, n = 0 }
  local lo, hi = it.lo, it.hi
  local S, c = hi - lo, (lo + hi) / 2
  local W = req("WtDamage")
  local B = req("Ballistics")
  local L = {}
  local carousel = (it.k == "ammo") and W.CAROUSEL[d.id] and not it.tur and A.style == "round"
  local cap = math.max(0, math.floor(rk.cap * scale))
  if not carousel then blk(L, V3(S.X, 0.06, S.Z), V3(c.X, lo.Y + 0.03, c.Z)) end   -- 弹架底板（空了也看得出弹架在哪）
  -- 这一架每格是哪种弹：按车上现在的 AmL 排（待发弹架现在有的那几发在前、车体弹架接着；打掉的弹种就不再画、不再写）
  local off = (it.k == "ammoH" and ctx.R.ammo) and math.min(ctx.R.ammo.n or 0, ctx.R.ammo.cap or 0) or 0
  local seq = A.seq or {}
  local kinds, names = {}, {}
  for i = 1, cap do
    local k = (#seq > 0) and seq[((off + i - 1) % #seq) + 1] or nil
    local a = k and B.AMMO and B.AMMO[k]
    kinds[i] = A.cls or (a and a.cls) or nil
    names[i] = a and a.name or nil
  end
  local per = 1
  if A.style == "none" then
    blk(L, S, c)
  elseif carousel then
    carouselRack(L, lo, hi, cap, MZ[d.id], one, ctx.crewR, ctx.carRmax)
    x.detail = "xr.d.carousel"
  elseif A.style == "cans" then
    canRack(L, lo, hi, cap, one)
    x.detail = "xr.d.cans"
  else
    local sep = A.sep and not one
    if sep then per = 2 end
    local tipDir
    if it.tur then tipDir = (c.Z >= 0) and 1 or -1 else tipDir = (c.Z < ctx.tp.Z) and -1 or 1 end   -- 弹底朝着装填的人
    gridRack(L, lo, hi, cap * per, A.dia, A.len, tipDir, (not sep) and kinds or nil, one, sep)
    x.detail = it.tur and "xr.d.bustle" or "xr.d.hullRack"
  end
  x.specs = L
  x.rack = { per = per, cap = cap, names = names, kinds = kinds }
  x.one, x.scale = one, scale   -- AmL 变了按同样的格数重排（客户端 reshape）
end

-- 反坦克导弹发射架（格）：发射筒长、筒径、弹径、几具、装在哪（炮塔顶 / 炮塔两侧 / 炮塔左侧 / 炮上面的导轨）
local ATGM = {
  konkurs = { len = 3.5, tube = 0.46, msl = 0.38, n = 1, at = "roof" },    -- 9M113「竞技」：炮塔顶上一具 9P135M 发射架（BMP-2，原模型量的位置）
  kornet = { len = 3.4, tube = 0.5, msl = 0.43, n = 4, at = "sides" },     -- 9M133「短号」：「海岸」战斗模块炮塔两侧各两具（BMP-2M）
  tow2 = { len = 3.4, tube = 0.56, msl = 0.43, n = 2, at = "left" },       -- BGM-71「陶-2」：炮塔左侧的双联装发射箱（M2A3）
  malyutka = { len = 2.4, tube = 0, msl = 0.35, n = 1, at = "rail" },      -- 9M14「婴儿」：炮上面的发射导轨（BMP-1）
}
XrayOwn.ATGM = ATGM
-- 发射架的零件（弹一发一格：slot；筒、导轨、支架不带 slot）；返回零件表、框架（tur / gun）、几具
local function launcherSpecs(d, ctx, wid)
  local A = ATGM[wid]
  if not A or not d.turret then return nil end
  local L = {}
  local ts = ctx.ts
  local topT = ctx.turTop - ctx.tp.Y   -- 炮塔顶（炮塔系）
  local base = topT - ts.Y
  local function tube(i, p, withTube)
    if withTube then rod(L, p + V3(0, 0, A.len / 2), p - V3(0, 0, A.len / 2), A.tube, "dk") end   -- 发射筒
    local n0 = #L
    rod(L, p + V3(0, 0, A.len / 2 - 0.2), p - V3(0, 0, A.len / 2 - 0.3), A.msl)                 -- 弹体
    rod(L, p - V3(0, 0, A.len / 2 - 0.3), p - V3(0, 0, A.len / 2 - 0.05), A.msl * 0.8, "tip")   -- 弹头
    mark(L, n0, i)
  end
  if A.at == "rail" then   -- 炮上面：一根导轨、导弹带四片尾翼（炮的框架，跟着俯仰）
    local g = d.gun
    local cal = (g and g.cal) or 0.25
    local p = V3(0, cal * 1.3 + 0.35, -0.7)
    bar(L, p + V3(0, -A.msl * 0.7, A.len * 0.45), p + V3(0, -A.msl * 0.7, -A.len * 0.45), 0.16, 0.1, "dk")   -- 导轨
    local n0 = #L
    rod(L, p + V3(0, 0, A.len / 2), p - V3(0, 0, A.len / 2 - 0.3), A.msl)
    rod(L, p - V3(0, 0, A.len / 2 - 0.3), p - V3(0, 0, A.len / 2), A.msl * 0.7, "tip")
    bar(L, p + V3(-0.55, 0, A.len * 0.32), p + V3(0.55, 0, A.len * 0.32), 0.3, 0.04)          -- 尾翼（展开）
    bar(L, p + V3(0, -0.55, A.len * 0.32), p + V3(0, 0.55, A.len * 0.32), 0.04, 0.3)
    mark(L, n0, 1)
    return L, "gun", 1
  end
  if A.at == "roof" then   -- 炮塔顶上一具（偏后：车长、炮长舱口中间）
    local p = V3(-ts.X * 0.04, topT + A.tube * 0.75, ts.Z * 0.1)
    blk(L, V3(0.3, A.tube * 0.6, 0.5), p - V3(0, A.tube * 0.6, -0.2), "dk")                    -- 支架
    tube(1, p, true)
  elseif A.at == "sides" then   -- 炮塔两侧各两具（上下叠着）
    local i = 0
    for s = -1, 1, 2 do
      local x = s * (ts.X / 2 + A.tube * 0.7)
      bar(L, V3(s * ts.X / 2, base + ts.Y * 0.5, 0.2), V3(x, base + ts.Y * 0.5, 0.2), 0.2, 0.2, "dk")   -- 支臂
      for j = 0, 1 do
        i += 1
        tube(i, V3(x, base + ts.Y * 0.4 + j * A.tube * 1.1, 0.2), true)
      end
    end
  else   -- 炮塔左侧的双联装发射箱（两个筒并排）
    local xc = -(ts.X / 2 + A.tube * 1.05)
    local y = base + ts.Y * 0.6
    bar(L, V3(-ts.X / 2, y, 0.3), V3(xc, y, 0.3), 0.25, 0.25, "dk")                            -- 支臂（发射箱升起来打）
    for i = 1, 2 do tube(i, V3(xc + (i - 1.5) * A.tube * 1.05, y, 0.3), true) end
  end
  return L, "tur", A.n
end

---------------------------------------------------------------- 整辆车的透视零件（纯数据，测试也能直接算）

local function catOf(it)
  if it.kind == "crew" then return "crew" end
  local k = it.k or ""
  if k == "engine" or k == "trans" or k == "breech" or k == "barrel" or k == "tdrive" or k == "optics" or k == "troops" then return k end
  if string.sub(k, 1, 4) == "fuel" then return "fuel" end
  if string.sub(k, 1, 4) == "ammo" then return "ammo" end
  if string.sub(k, 1, 5) == "track" then return "track" end
  return "other"
end
local BUILD = { engine = engineItem, trans = transItem, trackL = trackItem, trackR = trackItem, breech = breechItem, barrel = barrelItem,
  tdrive = tdriveItem, optics = opticsItem, fuelL = fuelItem, fuelR = fuelItem, troops = troopsItem }

-- opts：{ M = VehModels 的模型信息（爆反块）、live = 弹的现况 }；返回 { items = { { k, cat, frame = hull / tur / gun, specs, ci / mi（WtC / WtM 第几位）… } }, total, A, R, lay }
function XrayOwn.plan(d, opts)
  opts = opts or {}
  local W = req("WtDamage")
  local lay = W.layout(d)
  local ctx = mkCtx(d, lay)
  ctx.A = XrayOwn.ammoPlan(d, opts.live)
  ctx.R = XrayOwn.racksOf(ctx.A, d, lay, opts.live)
  local items, ammoX = {}, {}
  local ci, mi = 0, 0
  for _, it in ipairs(lay.list) do
    local x = { it = it, k = it.k, kind = it.kind, cat = catOf(it) }
    if it.k == "barrel" or it.k == "breech" then x.frame = "gun" elseif it.tur then x.frame = "tur" else x.frame = "hull" end
    if it.kind == "crew" then ci += 1 x.ci = ci else mi += 1 x.mi = mi end
    items[#items + 1] = x
  end
  local used = 0
  for _, x in ipairs(items) do   -- 先画弹药以外的（乘员在观瞄前面：炮长镜的目镜要对着炮长的脸）
    if x.cat == "ammo" then
      ammoX[#ammoX + 1] = x
    else
      local f = (x.kind == "crew") and crewItem or BUILD[x.k]
      if f then f(x, ctx) else
        local L = {}
        blk(L, x.it.hi - x.it.lo, (x.it.lo + x.it.hi) / 2)
        x.specs = L
      end
      used += #x.specs
    end
  end
  -- 篮子式转盘（T-64 / T-80）：炮塔里的人在竖药筒那一层的高度上，四肢伸到离转轴多远（竖药筒围在这一圈外面）
  local am = ctx.byK.ammo
  if MZ[d.id] and W.CAROUSEL[d.id] and am and not am.tur then
    local yTop = am.lo.Y + CAR_Y0 + CAR_DIA * 1.55 + CAR_CH - ctx.tp.Y   -- 竖药筒的顶（炮塔系）
    local r = 0
    for _, x in ipairs(items) do
      if x.kind == "crew" and x.it.tur and x.specs then
        for _, s in ipairs(x.specs) do
          local h = s.s / 2
          for _, k in ipairs(CORNERS) do
            local p = s.cf * (h * k)
            if p.Y < yTop then r = math.max(r, math.sqrt(p.X * p.X + p.Z * p.Z)) end
          end
        end
      end
    end
    ctx.crewR = r
  end
  -- 不算伤害的件：并列机枪（跟炮俯仰）、车长周视镜、车长热像仪
  local function extra(k, cat, frame, nm, L)
    if #L == 0 then return end
    items[#items + 1] = { k = k, kind = "extra", cat = cat, frame = frame, nm = nm, specs = L }
    used += #L
  end
  if d.coax and d.gun and d.turret then
    local L = {}
    local q = d.coax - d.gun.pivot
    blk(L, V3(0.24, 0.28, 0.95), q + V3(0, 0, 0.62))                                   -- 机匣
    rod(L, q + V3(0, 0, 0.12), q + V3(0, 0, -1.15), 0.09, "dk")                        -- 枪管
    blk(L, V3(0.3, 0.32, 0.42), q + V3((q.X >= 0) and 0.27 or -0.27, -0.12, 0.7))      -- 弹箱
    extra("coax", "breech", "gun", "xr.n.coax", L)
  end
  if d.cupola and d.turret then
    local L = {}
    local cp = d.cupola
    disc(L, cp + V3(0, 0.12, 0), 1.25, 0.26, "gl")                                     -- 指挥塔一圈观察镜
    blk(L, V3(0.46, 0.42, 0.5), cp + V3(0, 0.42, -0.3))                                -- 周视镜镜头
    bar(L, cp + V3(0, 0.25, -0.3), cp + V3(0, -0.55, -0.15), 0.26, 0.26)               -- 镜筒到车长眼前
    extra("csight", "optics", "tur", "xr.n.csight", L)
  end
  if d.citv and d.turret then
    local L = {}
    local p = V3(d.citv.X, ctx.ts.Y + 0.55, d.citv.Z)
    blk(L, V3(0.8, 0.85, 0.8), p)
    blk(L, V3(0.5, 0.35, 0.06), p + V3(0, 0.05, -0.42), "gl")
    rod(L, p - V3(0, 0.42, 0), p - V3(0, 0.95, 0), 0.3)
    extra("citv", "optics", "tur", "xr.n.citv", L)
  end
  -- 反坦克导弹发射架（BMP-1 / 2 / 2M、M2A3：第二件武器，原来只画主武器的弹架）：发射筒 + 筒里装着的导弹（打出去的那一发不画）
  for _, wid in ipairs(d.weapons or {}) do
    if ATGM[wid] and wid ~= ctx.A.wid then
      local L, frame, n = launcherSpecs(d, ctx, wid)
      if L and #L > 0 then
        items[#items + 1] = { k = "atgm", kind = "extra", cat = "ammo", frame = frame, nm = "xr.n.atgm", specs = L, launch = { wid = wid, cap = n } }
        used += #L
      end
      break
    end
  end
  -- 爆反块：模型上真的那些块（每块一件，按它在车体 / 炮塔上的位置、大小）
  local M = opts.M
  if M and M.era then
    local byG = { hull = {}, tur = {} }
    for i, e in ipairs(M.era) do
      if e.off and e.w and not e.off2 then
        local g = (e.g == "turret") and "tur" or "hull"
        local L = byG[g]
        local s = put(L, V3(e.w, e.h, e.t), e.off, "B")
        s.slot = i
      end
    end
    for g, L in pairs(byG) do
      if #L > 0 and used + #L <= LIMIT then
        items[#items + 1] = { k = "era", kind = "extra", cat = "era", frame = g, nm = "xr.era", specs = L, eraE = M.era }
        used += #L
      end
    end
  end
  -- 弹药最后：一发两个零件（弹体 + 弹头 / 弹丸 + 药筒 / 弹箱 + 弹链）；总数要超了一发一个，还超就少画几发
  local capSum = 0
  for _, x in ipairs(ammoX) do capSum += (ctx.R[x.k] and ctx.R[x.k].cap) or 0 end
  local left = LIMIT - used - #ammoX   -- 每架一块底板
  local one = capSum * 2 > left
  local scale = 1
  if one and capSum > left then scale = math.max(0, left / math.max(1, capSum)) end
  for _, x in ipairs(ammoX) do
    ammoItem(x, ctx, one, scale)
    used += #x.specs
  end
  -- 要几组 Highlight（类别 + 单独一组的子件；状态组另算，最多 5 个）
  local keys, nk = {}, 0
  for _, x in ipairs(items) do
    for _, s in ipairs(x.specs) do
      local k2 = s.g and (x.cat .. "_" .. s.g)
      local key = (k2 and SUBOK[k2]) and k2 or x.cat
      if not keys[key] then keys[key] = true nk += 1 end
    end
  end
  return { items = items, total = used, A = ctx.A, R = ctx.R, lay = lay, ctx = ctx, keys = keys, nKeys = nk }
end

-- 弹的现况变了（AmL：哪种弹打掉了几发；Rdy：待发弹架还剩几发）：同样的格数按现在的弹重排这一架——每格是哪种弹（提示框写的弹名）、
--   弹头的样子（脱壳穿甲弹细长、破甲弹粗）；返回新的一份（零件数、次序跟原来一样；格数变了返回 nil：整个重建）
function XrayOwn.relayRack(P, x, live)
  local ctx = P.ctx
  if not ctx or not x.rack then return nil end
  ctx.A.seq = XrayOwn.ammoPlan(ctx.d, live).seq
  local R = XrayOwn.racksOf(ctx.A, ctx.d, ctx.lay, live)
  for k, r in pairs(R) do
    local old = ctx.R[k]
    if old and old.cap ~= r.cap then return nil end
  end
  ctx.R = R
  local y = { it = x.it, k = x.k }
  ammoItem(y, ctx, x.one, x.scale)
  if #y.specs ~= #x.specs then return nil end
  return y
end

-- 一个乘员的人形零件（WtHud 的 X 光回放也用）：返回零件表（相对车的底座系；炮塔上的相对炮塔转轴）
function XrayOwn.crewSpecs(d, lay, it)
  local ctx = mkCtx(d, lay)
  local x = { it = it }
  crewItem(x, ctx)
  return x.specs
end

---------------------------------------------------------------- 客户端

function XrayOwn.init(G)
  local TH = G.Theme or req("Theme")
  local RGB = Color3.fromRGB
  local WHITE, BLACK = RGB(255, 255, 255), RGB(0, 0, 0)
  local function T(k, fb, ...)
    local s = G.T and G.T(k, ...)
    if s and s ~= k then return s end
    return fb or k
  end
  -- 类别的颜色（不用蓝；完好 / 受损 / 打坏的意思同 Theme：绿、琥珀、红）
  local PAL = {
    crew = TH.C.GOOD, engine = RGB(176, 124, 236), trans = RGB(146, 130, 184), fuel = RGB(64, 194, 176), ammo = RGB(236, 98, 168),
    breech = RGB(208, 210, 202), barrel = RGB(150, 156, 152), tdrive = RGB(170, 182, 100), optics = RGB(236, 240, 236),
    era = RGB(204, 188, 140), track = RGB(112, 116, 112), troops = RGB(158, 202, 150), other = TH.C.MUTE,
  }
  local STATE = { hurt = TH.C.WARN, broken = TH.C.BAD, kia = RGB(44, 34, 32), fire = RGB(255, 132, 40), hover = TH.C.TEXT }
  local function shade(c, sub)
    if sub == "dk" then return c:Lerp(BLACK, 0.4) end
    if sub == "tip" then return c:Lerp(WHITE, 0.5) end
    if sub == "gl" then return c:Lerp(RGB(26, 34, 32), 0.62) end
    return c
  end
  local function colOf(key)
    if STATE[key] then return STATE[key] end
    local cat, sub = string.match(key, "^(%a+)_(%a+)$")
    if cat then return shade(PAL[cat] or PAL.other, sub) end
    return PAL[key] or PAL.other
  end
  -- 图例：类别一行、状态一行
  local ORDER = { "crew", "engine", "trans", "fuel", "ammo", "breech", "barrel", "tdrive", "optics", "era", "track", "troops" }
  local LEG = { crew = { "xr.crew", "乘员" }, engine = { "xr.engine", "发动机" }, trans = { "xr.trans", "传动" }, fuel = { "xr.fuel", "油箱" },
    ammo = { "xr.ammo", "弹药" }, breech = { "xr.breech", "炮闩" }, barrel = { "xr.barrel", "炮管" }, tdrive = { "xr.tdrive", "炮塔驱动" },
    optics = { "xr.optics", "观瞄" }, era = { "xr.era", "爆反" }, track = { "xr.track", "履带 / 车轮" }, troops = { "xr.troops", "载员舱" },
    hurt = { "xr.hurt", "受损" }, broken = { "xr.broken", "打坏" }, kia = { "xr.kia", "阵亡" }, fire = { "xr.fire", "起火" } }

  local cur = nil
  local pool = {}
  local POOL_MAX = 700
  local stats = { made = 0, reused = 0, regroup = 0, builds = 0 }
  local SHAPE = { B = Enum.PartType.Block, S = Enum.PartType.Ball, C = Enum.PartType.Cylinder }
  local function take(sh)
    local p = table.remove(pool)
    if p then
      stats.reused += 1
    else
      p = Instance.new("Part")
      p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
      p.Material = Enum.Material.SmoothPlastic
      p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
      stats.made += 1
    end
    p.Shape = SHAPE[sh] or Enum.PartType.Block
    p.Transparency = 0
    return p
  end
  local function give(p)
    p.Parent = nil
    if #pool < POOL_MAX then pool[#pool + 1] = p else p:Destroy() end
  end

  -- 一组一个 Highlight（AlwaysOnTop：隔着车身也看得见）
  local function hlStyle(key)
    local c = colOf(key)
    if key == "kia" then return c, TH.C.BAD:Lerp(BLACK, 0.35), 0.15, 0.2 end
    if key == "broken" then return c, c:Lerp(WHITE, 0.3), 0.3, 0.1 end
    if key == "hurt" then return c, c:Lerp(WHITE, 0.3), 0.35, 0.1 end
    if key == "fire" then return c, RGB(255, 220, 140), 0.2, 0 end
    if key == "hover" then return c, WHITE, 0.3, 0 end
    return c, c:Lerp(WHITE, 0.4), 0.5, 0.15
  end
  local function group(c, key)
    local g = c.groups[key]
    if g then return g end
    if c.nG >= MAXG then   -- 组太多：子组并回大类
      local base = string.match(key, "^(%a+)_")
      if base then return group(c, base) end
    end
    g = Instance.new("Model")
    g.Name = "X_" .. key
    g.Parent = c.folder
    local h = Instance.new("Highlight")
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.FillColor, h.OutlineColor, h.FillTransparency, h.OutlineTransparency = hlStyle(key)
    h.Adornee, h.Parent = g, g
    c.groups[key], c.hls[key] = g, h
    c.nG += 1
    return g
  end
  local function keyOf(cat, sub)
    local k2 = sub and (cat .. "_" .. sub)
    if k2 and SUBOK[k2] then return k2 end
    return cat
  end

  ---------------------------------------------------------------- 屏幕上：图例、指着的部件
  local function label(parent, text, font, size, col, order)
    local t = Instance.new("TextLabel")
    t.LayoutOrder, t.AutomaticSize, t.Size = order or 0, Enum.AutomaticSize.X, UDim2.fromOffset(0, size + 4)
    t.BackgroundTransparency, t.Text, t.TextColor3 = 1, text, col or TH.C.TEXT
    t.Font, t.TextSize = font or TH.F.bold, size
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.TextStrokeTransparency, t.TextStrokeColor3 = TH.A.stroke, TH.C.INK
    t.Parent = parent
    return t
  end
  local function row(parent, order)
    local f = Instance.new("Frame")
    f.LayoutOrder, f.AutomaticSize, f.Size = order, Enum.AutomaticSize.X, UDim2.fromOffset(0, 20)
    f.BackgroundTransparency = 1
    local lay = Instance.new("UIListLayout")
    lay.FillDirection, lay.VerticalAlignment, lay.Padding = Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Center, UDim.new(0, 8)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = f
    f.Parent = parent
    return f
  end
  local function swatch(parent, key, order)
    local sw = Instance.new("Frame")
    sw.LayoutOrder, sw.Size, sw.BackgroundColor3, sw.BorderSizePixel = order, UDim2.fromOffset(12, 12), colOf(key), 0
    TH.corner(sw, 2)
    sw.Parent = parent
    local L = LEG[key]
    label(parent, T(L[1], L[2]), TH.F.bold, TH.S.small, TH.C.TEXT, order + 1)
  end
  local function buildGui(c)
    local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    local sg = Instance.new("ScreenGui")
    sg.Name, sg.ResetOnSpawn, sg.IgnoreGuiInset, sg.DisplayOrder = "OwnXrayLegend", false, true, 20
    local bar0 = Instance.new("Frame")
    bar0.Name = "Legend"
    bar0.AnchorPoint, bar0.Position, bar0.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -96), UDim2.fromOffset(0, 0)
    bar0.AutomaticSize = Enum.AutomaticSize.XY
    bar0.BackgroundColor3, bar0.BackgroundTransparency, bar0.BorderSizePixel = TH.C.PANEL, TH.A.bar, 0
    TH.corner(bar0)
    local lay = Instance.new("UIListLayout")
    lay.FillDirection, lay.HorizontalAlignment, lay.Padding = Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center, UDim.new(0, 2)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = bar0
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 4), UDim.new(0, 4)
    pad.Parent = bar0
    local r1, r2 = row(bar0, 1), row(bar0, 2)
    local n = 0
    for _, k in ipairs(ORDER) do
      if c.cats[k] then n += 2 swatch(r1, k, n) end
    end
    n = 0
    for _, k in ipairs({ "hurt", "broken", "kia", "fire" }) do
      if k ~= "kia" or c.cats.crew then n += 2 swatch(r2, k, n) end
    end
    bar0.Parent = sg
    -- 鼠标指着的部件：名字、状态、细节（弹药架几发、哪种弹……）
    local tip = Instance.new("Frame")
    tip.Name = "Tip"
    tip.AutomaticSize, tip.Size = Enum.AutomaticSize.XY, UDim2.fromOffset(0, 0)
    tip.BackgroundColor3, tip.BackgroundTransparency, tip.BorderSizePixel = TH.C.PANEL, TH.A.panel, 0
    tip.Visible = false
    TH.corner(tip)
    TH.stroke(tip)
    local tl = Instance.new("UIListLayout")
    tl.FillDirection, tl.Padding, tl.SortOrder = Enum.FillDirection.Vertical, UDim.new(0, 1), Enum.SortOrder.LayoutOrder
    tl.Parent = tip
    local tp = Instance.new("UIPadding")
    tp.PaddingLeft, tp.PaddingRight, tp.PaddingTop, tp.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 4), UDim.new(0, 5)
    tp.Parent = tip
    c.tipName = label(tip, "", TH.F.bold, TH.S.body, TH.C.TEXT, 1)
    c.tipName.Name = "Name"
    c.tipState = label(tip, "", TH.F.bold, TH.S.small, TH.C.GOOD, 2)
    c.tipState.Name = "State"
    c.tipInfo = label(tip, "", TH.F.bold, TH.S.small, TH.C.MUTE, 3)
    c.tipInfo.Name = "Info"
    tip.Parent = sg
    c.tip = tip
    sg.Parent = pg
    return sg
  end

  ---------------------------------------------------------------- 建 / 清

  local function liveOf(st)
    local em = st.em
    local live = { rdy = em:GetAttribute("Rdy"), rdyCap = em:GetAttribute("RdyCap"), aml = em:GetAttribute("AmL") }
    local wid = XrayOwn.mainWeapon(st.d)
    local vs = G.S and G.S.veh
    if wid and vs and (vs.id == nil or vs.id == st.id) and type(vs.ammo) == "table" then
      local am = vs.ammo[wid]
      if type(am) == "table" and type(am[1]) == "number" and type(am[2]) == "number" then live.total = am[1] + am[2] end
    end
    if live.total == nil and type(live.aml) == "string" then
      local s, any = 0, false
      for n in string.gmatch(live.aml, ":(%d+)") do s += tonumber(n) any = true end
      if any then live.total = s end
    end
    -- 反坦克导弹：发射筒里还装着几发（客户端的弹数 { 装着的, 备弹 }）
    for _, w2 in ipairs(st.d.weapons or {}) do
      if XrayOwn.ATGM[w2] and vs and (vs.id == nil or vs.id == st.id) and type(vs.ammo) == "table" then
        local am = vs.ammo[w2]
        if type(am) == "table" and type(am[1]) == "number" then live.msl = am[1] end
        break
      end
    end
    return live
  end
  -- 发射架上画几发：装着几发就几发（拿不到弹数按装满）
  local function launchN(x, live) return math.clamp(math.floor(tonumber(live.msl) or x.launch.cap), 0, x.launch.cap) end

  local function clear()
    local c = cur
    if not c then return end
    cur = nil
    for _, x in ipairs(c.items) do
      for _, q in ipairs(x.parts or {}) do give(q.p) end
      x.parts = nil
    end
    if c.folder then c.folder:Destroy() end
    if c.gui then c.gui:Destroy() end
    for _, f in ipairs(c.faded or {}) do
      if f[1].Parent then f[1].LocalTransparencyModifier = f[2] end
    end
  end

  local function build(st)
    local d = st.d
    local v = G.views and G.views[st.em]
    -- Highlight 全客户端同时最多画 31 个：第三人称车辆热成像（Night.lua，1 + 最多 24 个）先让开，透视（最多 MAXG 组 + 车身轮廓）一个人用
    if G.vehIrHide then pcall(G.vehIrHide) end
    local live = liveOf(st)
    local ok, P = pcall(XrayOwn.plan, d, { M = v and v.M, live = live })
    if not ok or not P then
      if G.showError then G.showError("local XrayOwn: " .. tostring(P)) end
      return nil
    end
    stats.builds += 1
    local c = { st = st, v = v, d = d, P = P, items = P.items, A = P.A, lay = P.lay, groups = {}, hls = {}, nG = 0, cs = {}, seatS = {}, ms = {}, cats = {}, dirty = true }
    c.liveSig = tostring(live.total) .. "/" .. tostring(live.rdy) .. "/" .. tostring(live.rdyCap) .. "/" .. tostring(live.aml) .. "/" .. tostring(live.msl)   -- 同 sigOf：建的时候就是按这一份画的
    c.folder = Instance.new("Folder")
    c.folder.Name = "OwnXray"
    for _, x in ipairs(c.items) do
      c.cats[x.cat] = true
      x.parts, x.ov = {}, nil
      for i, sp in ipairs(x.specs) do
        local p = take(sp.sh)
        p.Size = sp.s
        local col = shade(PAL[x.cat] or PAL.other, sp.g)
        p.Color = col
        p.Name = x.k
        x.parts[i] = { p = p, cf = sp.cf, key = keyOf(x.cat, sp.g), col = col, slot = sp.slot, vis = true }
      end
    end
    -- 弹架：只画现在有的那几发；炸掉的爆反块不画
    for _, x in ipairs(c.items) do
      if x.rack then
        local rk = P.R[x.k]
        local n = math.min((rk and rk.n) or 0, x.rack.cap)
        local vis = n * x.rack.per
        x.rack.vis, x.rack.n = vis, n
        for _, q in ipairs(x.parts) do q.vis = (q.slot == nil) or (q.slot <= vis) end
      elseif x.launch then
        local n = launchN(x, live)
        x.launch.n = n
        for _, q in ipairs(x.parts) do q.vis = (q.slot == nil) or (q.slot <= n) end
      elseif x.eraE then
        for _, q in ipairs(x.parts) do
          local e = x.eraE[q.slot]
          q.vis = e ~= nil and not e.blown
        end
      end
    end
    for _, x in ipairs(c.items) do
      for _, q in ipairs(x.parts) do if q.vis then q.p.Parent = group(c, q.key) end end
    end
    -- 车身：半透明的壳（原来的透明度记着，松手还原）+ 轮廓线
    c.faded = {}
    local m = v and v.model
    if m then
      for _, q in ipairs(m:GetDescendants()) do
        if q:IsA("BasePart") and q.Transparency < 0.95 then
          c.faded[#c.faded + 1] = { q, q.LocalTransparencyModifier }
          q.LocalTransparencyModifier = math.max(q.LocalTransparencyModifier, 0.82)
        end
      end
      local hl = Instance.new("Highlight")
      hl.Name = "Hull"
      hl.DepthMode = Enum.HighlightDepthMode.Occluded
      hl.FillTransparency, hl.OutlineTransparency, hl.OutlineColor = 1, 0.3, TH.C.LINE
      hl.Adornee, hl.Parent = m, c.folder
    end
    c.folder.Parent = workspace
    c.gui = buildGui(c)
    return c
  end

  ---------------------------------------------------------------- 每帧

  -- 乘员按座位（服务器 WtC 每个人是「状态 .. 现在的座位」，Wt.lua：装填手顶上阵亡的炮长以后「2gnr,0ldr」——炮长位上是活人、
  --   装填手位空了；同 WtTank 损伤图的读法：一个座位取状态最好的那个，WtC 里没这个座位的算没人）；老格式（只有状态没有座位）按顺序
  local function parseStates(c, em)
    local wc, wm = em:GetAttribute("WtC"), em:GetAttribute("WtM")
    if wc == c.wc and wm == c.wm then return end
    c.wc, c.wm = wc, wm
    local cs, seat, named, ms = {}, {}, false, {}
    local i = 0
    for tok in string.gmatch(type(wc) == "string" and wc or "", "[^,]+") do
      i += 1
      local s, sn = tonumber(string.sub(tok, 1, 1)) or 2, string.sub(tok, 2)
      cs[i] = s
      if sn ~= "" then
        named = true
        if seat[sn] == nil or s > seat[sn] then seat[sn] = s end
      end
    end
    if type(wm) == "string" then for j = 1, #wm do ms[j] = tonumber(string.sub(wm, j, j)) or 2 end end
    c.cs, c.seatS, c.named, c.ms = cs, seat, named, ms
  end
  local function crewS(c, x)
    if c.named then return c.seatS[(x.it and x.it.role) or x.k] or 0 end
    return c.cs[x.ci] or 2
  end
  -- 这一件现在该在哪个状态组（nil = 按类别）
  local function stateKey(c, x)
    if x.ci then
      local s = crewS(c, x)
      if s == 0 then return "kia" end
      if s == 1 then return "hurt" end
      return nil
    end
    if x.mi then
      local s = c.ms[x.mi] or 2
      if s == 0 then return "broken" end
      if c.afire and x.cat == "ammo" and (not x.rack or x.rack.vis > 0) then return "fire" end
      if c.fire and not c.afire and (x.k == "engine" or x.cat == "fuel") then return "fire" end
      if s == 1 then return "hurt" end
    end
    return nil
  end
  local function setOv(c, x, ov)
    if x.ov == ov then return end
    x.ov = ov
    local col = ov and ((ov == "hover") and c.hoverCol or STATE[ov]) or nil
    for _, q in ipairs(x.parts) do
      q.p.Color = col or q.col
      if q.vis then q.p.Parent = group(c, ov or q.key) end
    end
    stats.regroup += 1
  end
  local function setVis(c, x, q, want)
    if q.vis == want then return end
    q.vis = want
    q.p.Parent = want and group(c, x.ov or q.key) or nil
    c.dirty = true
  end
  local function rebuildMoves(c)
    local P, F, O, X, S, Sl = {}, {}, {}, {}, {}, {}
    for _, x in ipairs(c.items) do
      for _, q in ipairs(x.parts) do
        if q.vis then
          local n = #P + 1
          P[n], F[n], O[n], X[n], S[n], Sl[n] = q.p, x.frame, q.cf, x, q.p.Size, q.slot
        end
      end
    end
    c.mP, c.mF, c.mO, c.mX, c.mS, c.mSl, c.mC = P, F, O, X, S, Sl, {}
    c.dirty = false
  end

  -- 射线（世界）打零件：近似成方盒
  local function slab(p, dd, h, t0, t1)
    if math.abs(dd) < 1e-9 then
      if p < -h or p > h then return 1, 0 end
      return t0, t1
    end
    local a, b = (-h - p) / dd, (h - p) / dd
    if a > b then a, b = b, a end
    if a > t0 then t0 = a end
    if b < t1 then t1 = b end
    return t0, t1
  end
  local function rayBox(o, dv, cf, size)
    local lo = cf:PointToObjectSpace(o)
    local ld = cf:VectorToObjectSpace(dv)
    local t0, t1 = slab(lo.X, ld.X, size.X / 2, 0, 1)
    if t0 > t1 then return nil end
    t0, t1 = slab(lo.Y, ld.Y, size.Y / 2, t0, t1)
    if t0 > t1 then return nil end
    t0, t1 = slab(lo.Z, ld.Z, size.Z / 2, t0, t1)
    if t0 > t1 then return nil end
    return t0
  end
  local function pick(c, px, py)
    local cam = workspace.CurrentCamera
    if not cam or not c.mP then return nil end
    local ray = cam:ViewportPointToRay(px, py)
    local o, dv = ray.Origin, ray.Direction * 600
    local best, bx, bs = math.huge, nil, nil
    for i = 1, #c.mP do
      local cf = c.mC[i]
      if cf then
        local t = rayBox(o, dv, cf, c.mS[i])
        if t and t < best then best, bx, bs = t, c.mX[i], c.mSl[i] end
      end
    end
    return bx, bs
  end

  local function nameOf(x)
    if x.kind == "crew" then return T("wt.r." .. ((x.it and x.it.role) or x.k), x.k) end
    if x.nm then return T(x.nm, x.k) end
    return T("wt.m." .. x.k, x.k)
  end
  -- 状态的一行：文字、颜色
  local function stateText(c, x)
    local st, col = nil, TH.C.GOOD
    if x.ci then
      local s = crewS(c, x)
      if s == 0 then st, col = T("xr.s.kia", "阵亡"), TH.C.BAD
      elseif s == 1 then st, col = T("xr.s.wounded", "受伤"), TH.C.WARN
      else st = T("xr.s.ok", "完好") end
    elseif x.mi then
      local s = c.ms[x.mi] or 2
      if s == 0 then st, col = T("xr.s.broken", "损毁"), TH.C.BAD
      elseif s == 1 then st, col = T("xr.s.hurt", "受损"), TH.C.WARN
      else st = T("xr.s.ok", "完好") end
      if stateKey(c, x) == "fire" or (s == 0 and ((c.afire and x.cat == "ammo") or (c.fire and not c.afire and (x.k == "engine" or x.cat == "fuel")))) then
        st, col = st .. " · " .. T("xr.s.fire", "起火"), (s == 0) and TH.C.BAD or STATE.fire
      end
    elseif x.k == "era" then
      st = T("xr.s.ok", "完好")
    end
    return st, col
  end
  local function infoText(c, x, slot)
    local bits = {}
    if x.detail then bits[#bits + 1] = T(x.detail, "") end
    if x.rack then
      bits[#bits + 1] = T("xr.d.rounds", tostring(x.rack.n) .. " / " .. tostring(x.rack.cap), x.rack.n, x.rack.cap)
      local i = slot and math.ceil(slot / x.rack.per) or nil
      local nm = i and x.rack.names and x.rack.names[i]
      if nm then bits[#bits + 1] = nm end
    elseif x.launch then   -- 发射架：装着几发、哪种导弹
      bits[#bits + 1] = T("xr.d.rounds", tostring(x.launch.n or 0) .. " / " .. tostring(x.launch.cap), x.launch.n or 0, x.launch.cap)
      bits[#bits + 1] = T("vw." .. x.launch.wid, x.launch.wid)
    end
    if (x.k == "barrel" or x.k == "breech") and c.A and c.A.cal then bits[#bits + 1] = T("xr.d.mm", c.A.cal .. " mm", c.A.cal) end
    local out = {}
    for _, b in ipairs(bits) do if b ~= "" then out[#out + 1] = b end end
    return table.concat(out, " · ")
  end
  local function setHover(c, x, slot, mx, my)
    if c.hoverX ~= x then
      local old = c.hoverX
      c.hoverX = x
      if old then setOv(c, old, stateKey(c, old)) end
      if x then
        local sk = stateKey(c, x)
        c.hoverCol = (sk and STATE[sk] or PAL[x.cat] or PAL.other):Lerp(WHITE, 0.35)
        local g = group(c, "hover")
        local h = c.hls.hover
        if h and g then h.FillColor = c.hoverCol end
        setOv(c, x, "hover")
      end
    end
    local tip = c.tip
    if not tip then return end
    if not x then tip.Visible = false return end
    c.tipName.Text = nameOf(x)
    local st, col = stateText(c, x)
    c.tipState.Text, c.tipState.TextColor3, c.tipState.Visible = st or "", col, st ~= nil
    local info = infoText(c, x, slot)
    c.tipInfo.Text, c.tipInfo.Visible = info, info ~= ""
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
    tip.Position = UDim2.fromOffset(math.clamp(mx + 18, 0, math.max(0, vp.X - 220)), math.clamp(my - 10, 0, math.max(0, vp.Y - 80)))
    tip.Visible = true
  end

  local holding = false
  local hoverT = 0
  -- 指针在哪（视口像素）：电脑上鼠标没锁在屏幕中间的时候（按住 X 时 Drive 放开鼠标、显示指针）；手机上刚点过的那一下（4 秒内）；
  --   都没有返回 nil：不显示提示框（原来鼠标一直锁在中间，提示框钉在屏幕中间、只指得到炮管）
  local tapAt = nil
  local function pointer()
    if UIS.MouseEnabled and UIS.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
      local m = UIS:GetMouseLocation()
      return m.X, m.Y
    end
    if tapAt and os.clock() - tapAt.t < 4 then return tapAt.x, tapAt.y end
    return nil
  end
  pcall(function()
    UIS.TouchTap:Connect(function(pos, processed)   -- 手机：按住透视键的时候另一只手指点一下部件
      if processed or not holding or not cur or type(pos) ~= "table" or not pos[1] then return end
      local inset = 0
      pcall(function() inset = game:GetService("GuiService"):GetGuiInset().Y end)   -- 触点不算顶栏；ViewportPointToRay 算
      tapAt = { x = pos[1].X, y = pos[1].Y + inset, t = os.clock() }
      hoverT = 0
    end)
  end)
  local function sigOf(live) return tostring(live.total) .. "/" .. tostring(live.rdy) .. "/" .. tostring(live.rdyCap) .. "/" .. tostring(live.aml) .. "/" .. tostring(live.msl) end
  -- 弹的现况变了：按现在的 AmL 重排每一架（每格哪种弹、弹头的样子），再只画现在有的那几发；格数变了返回 false（整个重建）
  local function liveChanged(c, live)
    for _, x in ipairs(c.items) do
      if x.rack then
        local y = XrayOwn.relayRack(c.P, x, live)
        if not y then return false end
        x.rack.names, x.rack.kinds, x.specs = y.rack.names, y.rack.kinds, y.specs
        for i, sp in ipairs(y.specs) do
          local q = x.parts[i]
          q.cf = sp.cf
          if q.p.Size ~= sp.s then q.p.Size = sp.s end
        end
        c.dirty = true
      end
    end
    local R = c.P.ctx.R
    for _, x in ipairs(c.items) do
      if x.rack then
        local n = math.min(R[x.k] and R[x.k].n or 0, x.rack.cap)
        local vis = n * x.rack.per
        x.rack.n = n
        if vis ~= x.rack.vis then
          x.rack.vis = vis
          for _, q in ipairs(x.parts) do setVis(c, x, q, (q.slot == nil) or (q.slot <= vis)) end
        end
      elseif x.launch then   -- 导弹打出去一发：那一筒空了
        local n = launchN(x, live)
        x.launch.n = n
        for _, q in ipairs(x.parts) do setVis(c, x, q, (q.slot == nil) or (q.slot <= n)) end
      end
    end
    return true
  end
  local function step()
    if not holding then return end
    local st = G.drive
    if not st or not st.em or not st.em.Parent or not st.root or not st.d then holding = false clear() return end
    -- 瞄准镜、车长望远镜、车内视角里不画（零件就在镜头边上，高亮糊满屏）：先收起，退出来（还按着）接着画
    if st.sight or st.binoc or (G.interiorOn and G.interiorOn()) then
      if cur then clear() end
      return
    end
    if not cur or cur.st ~= st then
      clear()
      cur = build(st)
      if not cur then holding = false return end
    end
    local c, d, em = cur, st.d, st.em
    local v = G.views and G.views[em]
    -- 框架：跟 View 摆原模型的同一套（车体晃动、炮塔方位、炮的俯仰和后坐都对得上）；没有 View 按 st 算
    local hullF = (v and v.hullF) or (st.root * CF(0, -d.H / 2, 0))
    local tF = (v and v.tF) or (d.turret and (hullF * CF(d.turret.pivot) * ANG(0, -RAD(st.ty or 0), 0))) or hullF
    local gF = (v and v.gF) or (d.gun and (tF * CF(d.gun.pivot) * ANG(RAD(st.gp or 0), 0, 0))) or tF
    c.fr = { hull = hullF, tur = tF, gun = gF }
    parseStates(c, em)
    c.fire, c.afire = em:GetAttribute("WtF") == true, em:GetAttribute("WtAF") == true
    -- 弹：打一发少一发、哪种弹打掉了（车上属性、客户端的弹数变了才重算）
    local live = liveOf(st)
    local sig = sigOf(live)
    if sig ~= c.liveSig then
      c.liveSig = sig
      if not liveChanged(c, live) then   -- 弹架格数变了（换了弹药配置）：下一帧整个重建
        clear()
        return
      end
    end
    -- 爆反块炸掉了：那一块不画
    for _, x in ipairs(c.items) do
      if x.eraE then
        for _, q in ipairs(x.parts) do
          local e = x.eraE[q.slot]
          setVis(c, x, q, e ~= nil and not e.blown)
        end
      end
    end
    for _, x in ipairs(c.items) do
      if x ~= c.hoverX then setOv(c, x, stateKey(c, x)) end
    end
    if c.dirty then rebuildMoves(c) end
    local fr, C, P, Fk, O = c.fr, c.mC, c.mP, c.mF, c.mO
    for i = 1, #P do C[i] = fr[Fk[i]] * O[i] end
    for i = #P + 1, #C do C[i] = nil end
    if #P > 0 then workspace:BulkMoveTo(P, C, Enum.BulkMoveMode.FireCFrameChanged) end
    -- 起火：火光色一闪一闪
    local fh = c.hls.fire
    if fh then
      local k = 0.5 + 0.5 * math.sin(os.clock() * 13)
      fh.FillColor = RGB(255, 92, 30):Lerp(RGB(255, 196, 70), k)
      fh.FillTransparency = 0.12 + 0.25 * (1 - k)
    end
    -- 指着的部件（一秒二十次）：没有指针不显示提示框
    local now = os.clock()
    if now - hoverT >= 0.05 then
      hoverT = now
      local px, py = pointer()
      if px then
        local x, slot = pick(c, px, py)
        setHover(c, x, slot, px, py)
      else
        setHover(c, nil)
      end
    end
  end

  function G.ownXrayOn() return holding and cur ~= nil end
  function G.ownXrayHold(down)
    holding = down and true or false
    if not holding then clear() end
  end
  G.ownXrayToggle = function() G.ownXrayHold(not holding) return holding end   -- 老的调用（测试）还能用
  G.ownXrayPlan = XrayOwn.plan
  -- 测试看的：零件数、各件几个零件、弹架几发、Highlight 几组、对象池
  function G.ownXrayInfo()
    local c = cur
    if not c then return { on = false, pooled = #pool, stats = stats } end
    local info = { on = true, pooled = #pool, stats = stats, parts = 0, shown = 0, items = {}, crew = {}, racks = {}, groups = c.nG, hover = c.hoverX and c.hoverX.k or nil }
    for _, x in ipairs(c.items) do
      local n, sh = #x.parts, 0
      for _, q in ipairs(x.parts) do if q.vis then sh += 1 end end
      info.parts += n
      info.shown += sh
      local key = (x.k == "era") and ("era_" .. x.frame) or x.k
      info.items[key] = { n = n, shown = sh, cat = x.cat, frame = x.frame, ov = x.ov, parts = x.parts }
      if x.kind == "crew" then info.crew[(x.it and x.it.role) or x.k] = sh end
      if x.rack then info.racks[x.k] = { n = x.rack.n, cap = x.rack.cap, per = x.rack.per, shown = sh, names = x.rack.names } end
      if x.launch then info.launch = { n = x.launch.n, cap = x.launch.cap, wid = x.launch.wid, shown = sh } end
    end
    local hl = 0
    for _, o in ipairs(c.folder:GetDescendants()) do if o:IsA("Highlight") then hl += 1 end end
    info.hl = hl
    return info
  end
  -- 测试：屏幕上这一点指着哪一件（返回键、名字）
  function G.ownXrayPick(px, py)
    local c = cur
    if not c then return nil end
    local x, slot = pick(c, px, py)
    if not x then return nil end
    return x.k, nameOf(x), slot
  end
  -- 每帧：init.client.lua 的 steps 里排在 view（还有 interior / ride / hatch）后面调——View 这一帧摆好车模、算好车体 / 炮塔 / 炮的框架以后
  --   再摆透视零件（原来单独连 RenderStepped，跟 View 谁先跑没保证：先跑就比车壳晚一帧，开起来里面的零件发飘）
  G.stepOwnXray = function()
    local ok, err = pcall(step)
    if not ok then
      holding = false
      pcall(clear)
      if G.showError then G.showError("local XrayOwn: " .. tostring(err)) end
    end
  end
  if not G.frameConn then RunService.RenderStepped:Connect(G.stepOwnXray) end   -- 单独跑（没有主循环）的时候自己连
end

return XrayOwn
