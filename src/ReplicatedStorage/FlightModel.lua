-- 全面大战场——固定翼飞机的飞行物理（客户端 Fly.lua 开飞机用；纯数字计算，不碰 Roblox 对象，Lune 能直接跑：tools/test/flight.luau）
--   用户 11-26 晚：「重量、推力（推重比）：决定加速快不快、爬升和急转后能不能补回能量；翼面积（翼载）、最大升力系数：决定转弯能多急、多久掉速；
--     零升阻力、诱导阻力、跨音速波阻：决定松油门掉速快不快、急转掉能量多不多；过载上限、失速迎角：决定能拉多狠、什么时候失速；
--     转动惯量（俯仰、滚转、偏航）：决定机头起转和停住时是脆还是肉；静稳定性、阻尼：决定松杆后飞机是自己稳住还是晃来晃去」
--   「每个飞机要有不同的参数」「现在飞机驾驶感觉过于灵敏」
--
--   六自由度刚体：速度（世界坐标）、姿态（四元数，跟 Roblox CFrame 同一个约定：机体 X 右、Y 上、Z 后）、机体角速度（滚转 p、俯仰 q、偏航 r，
--     前右下的习惯：p 右翼往下、q 抬头、r 机头往右为正），每帧切成 1/120 秒的小步积分。
--   气动（每型自己的系数）：升力（线性段 → 圆滑到最大升力系数 → 失速后掉成平板升力）、零升阻力 + 诱导阻力 + 跨音速 / 超音速波阻 + 大迎角阻力、侧力；
--     俯仰 / 滚转 / 偏航力矩：静稳定（静稳定裕度 → Cmα）、阻尼（Cmq、Clp、Cnr）、上反效应（Clβ）、航向静稳定（Cnβ）、舵面；陀螺耦合项。
--     失速：一边机翼先掉（翼尖先失速）、滚转阻尼变正（自转，尾旋的起因）、大迎角航向静稳定变负（偏离）。
--   发动机：军推 + 加力，转速有惯性（慢车到军推几秒，加力点火要一下），推力随马赫数、空气密度变；涡桨（无人机）按功率；推力矢量（喷口偏转产生力矩）。
--   操纵（每型照真机）：
--     fbw 电传（数字 / 模拟）：拉杆 → 过载指令、压杆 → 滚转角速度指令（松杆保持坡度、小坡度自己改平），迎角限制、过载限制、偏航阻尼与协调转弯；
--         舵面用动态逆（按当前动压求要多大舵偏才得到想要的角加速度）算，舵偏、舵偏速率有限，增益（带宽）按型号——重的、老的电传慢一些
--     cas 增稳 / 控制增强（F-15、F-14、米格-29）：同上但增益低、没有硬的迎角限制（拉到最大升力系数为止）
--     mech 机械操纵（歼-6、歼-8、A-10、苏-25、轰-6K）：杆直接对舵面（按动压排的传动比：高速满杆不至于一下拉爆，低速满杆能拉进失速），
--         阻尼器（有的型号有俯仰 / 偏航阻尼器），自动配平到 1 g；松杆后按自己的短周期 / 荷兰滚模态回稳——稳定性、阻尼不同，晃的样子就不同
--     教官 / 自动驾驶（鼠标瞄准、光电吊舱、飞出作战区自动掉头、无人机）给的是过载 + 滚转角速度指令，机械操纵的飞机也按动态逆飞（带宽低一些、不进失速）
--   数据：公开资料（官方、厂家手册、简氏、维基百科引的出处）；官方没公布的（歼-20、歼-35、歼-36、攻击-11 的重量 / 翼面积 / 推力、各型的气动导数）按外界估算，
--     转动惯量按回转半径估（F-16 照 Stevens & Lewis 的数据标定：Ixx = m (kx·b)²、Iyy = m (ky·L)²、Izz = m (kz·(b + L) / 2)²），见各行注释
local FM = {}
local G0 = 9.80665
local RAD = math.pi / 180
local sin, cos, sqrt, abs, exp, atan2, asin = math.sin, math.cos, math.sqrt, math.abs, math.exp, math.atan2, math.asin
FM.DT = 1 / 120
FM.G = G0
-- 收住滚转的刹车（1/秒，FM.sub 积分前那段；用户 11-28「滚筒做着突然不做 惯性要能收住」，又「你减少三分之一的角度」）：
--   满速滚转松杆多滚的角度比只靠副翼时少三分之一（F-16 71° → 47°、苏-27 76° → 49°、歼-6 41° → 30°）——
--   电传 / 增稳 / 教官飞 4.5，机械操纵松杆 2（没有飞控，同样的刹车对它们收得更狠）；各型可以在自己那一行写 rollBrake 改
local ROLL_BRAKE, ROLL_BRAKE_MECH = 4.5, 2
FM.ROLL_BRAKE = ROLL_BRAKE
-- 转弯机动性（用户 11-28「我指的机动性 是我飞行转向的机动性 稍微高一点」；战雷的飞机也比真机灵一点）：
--   整条升力曲线 × lift（失速迎角不变：同一个迎角升力多一成）、诱导阻力 × ind——升力限制的那一段（拐角速度以下）瞬时转弯率、
--   推力限制的持续盘旋率各高约一成；过载限制、极速、零升阻力不变。FM.get 建表时乘（F-14 收后掠那一套 FM.sweep 里也乘）
local AGILE = { lift = 1.1, ind = 0.83 }
FM.AGILE = AGILE

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function lerp(a, b, t) return a + (b - a) * t end
local function smooth(a, b, x) local t = clamp((x - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
local function moveTo(cur, want, step) if cur < want then return math.min(want, cur + step) end return math.max(want, cur - step) end
FM.clamp, FM.lerp, FM.smooth = clamp, lerp, smooth

-- 国际标准大气（对流层 + 平流层底）：密度 kg/m³、声速 m/s
function FM.atmo(h)
  h = clamp(h or 0, -500, 20000)
  local T = math.max(216.65, 288.15 - 0.0065 * h)
  local rho = (h < 11000) and 1.225 * (T / 288.15) ^ 4.25588 or 0.36392 * exp(-(h - 11000) / 6341.6)
  return rho, sqrt(1.4 * 287.05 * T)
end

---------------------------------------------------------------- 每型的物理量

-- 没写的按这一套（喷气战斗机的常见量级）：
--   m0 空重 kg、fi 机内燃油 kg、S 翼面积 m²、b 翼展 m、c 平均气动弦长 m、L 机长 m、Tm / Ta 军推 / 加力总推力 N（海平面静推力）、
--   lap 推力随马赫数的变化（军推 1 − lap[1]·M + lap[2]·M²；涵道比越大掉得越多）、CLa 升力线斜率 /rad、aS 失速迎角°、CLm 最大升力系数、
--   CD0 零升阻力系数、e 奥斯瓦尔德效率（诱导阻力因子 K = 1 / (π·展弦比·e)；给了 K 就用 K）、Mcr 阻力发散马赫数、CDw 跨声速波阻峰值（加在 CD0 上）、
--   nz 过载限制 {负, 正}、aL 电传的迎角限制°（没有就是 nil）、pmax 最大滚转角速度°/s、fcs 操纵（fbw / cas / mech）、bw 飞控带宽倍数、
--   tn / tp 过载 / 滚转指令的前置滤波时间常数（秒）、sm 静稳定裕度（平均气动弦长的几成；负的是放宽静稳定，要电传才飞得了）、
--   Cmq Clp Cnr 俯仰 / 滚转 / 偏航阻尼导数、Cnb 航向静稳定、Clb 上反效应、CYb 侧力、Cmde 平尾（升降舵 / 鸭翼）操纵导数 /rad、
--   Clda 副翼（没写就按最大滚转角速度反推）、Cndr 方向舵、de da dr 舵偏上限°、rde rda rdr 舵偏速率°/s、kx ky kz 回转半径系数、
--   sb 减速板的阻力系数增量、gearCD 起落架、flapCL 襟翼的升力增量、up / dn 发动机慢车 → 军推 / 军推 → 慢车的秒数、ab 加力点火的秒数、
--   vne 海平面最大允许速度 m/s（超了撕翼，WtAir）、Kq Kr 机械操纵的俯仰 / 偏航阻尼器（舵偏 rad / 角速度 rad/s）、
--   qmax 教官拉杆的最大俯仰角速度 rad/s、pu 失速前上仰（后掠翼的翼尖先失速）、tvc 推力矢量 { p 俯仰°, y 偏航°, r 速率°/s }、
--   prop 涡桨 { P 功率 W, Tst 静推力 N, eta 螺旋桨效率 }、cmS 失速后的低头力矩系数（苏-27 系小：真机不靠推力矢量也能拉眼镜蛇）
local BASE = {
  ne = 2, lap = { 0.15, 0.1 }, CLa = 3.5, aS = 30, CLm = 1.6, CD0 = 0.02, e = 0.8, Mcr = 0.88, CDw = 0.03,
  nz = { -3, 9 }, pmax = 200, fcs = "fbw", bw = 1, sm = -0.03,
  Cm0 = 0, Cmq = -5, Clp = -0.3, Cnr = -0.28, Cnb = 0.11, Clb = -0.08, CYb = -0.9, Clr = 0.05, Cnp = -0.02,
  Cmde = -0.8, Cndr = -0.065, CYdr = 0.15, Cnda = -0.005, Cldr = 0.01,
  de = 25, da = 21, dr = 30, rde = 60, rda = 100, rdr = 120,
  kx = 0.115, ky = 0.18, kz = 0.23, sb = 0.05, gearCD = 0.02, flapCL = 0.35, up = 3.5, dn = 2.5, ab = 0.4,
  Kq = 0, Kr = 0, qmax = 0.5, pu = 0, cmS = 0.25,
}

FM.AC = {
  -- —— 解放军 ——
  -- 歼-6（米格-19S 的仿制）：两台涡喷-6（军推各 25.5 千牛、加力 31.9 千牛），55° 后掠中单翼带翼刀；机械操纵（助力），静稳定；
  --   翼刀压不住翼尖失速，大迎角前有上仰（pu）；跨声速波阻大（早期的超音速设计），海平面极速约 1150 公里 / 时
  j6 = { m0 = 5450, fi = 1740, S = 25.0, b = 9.0, c = 3.06, L = 12.54, Tm = 51000, Ta = 63800, lap = { 0.1, 0.12 },
    CLa = 3.5, aS = 18, CLm = 1.1, CD0 = 0.0205, e = 0.6, Mcr = 0.86, CDw = 0.05, nz = { -3, 8 }, pmax = 165, fcs = "mech", bw = 0.55, sm = 0.07,
    Cmq = -6.5, Clp = -0.30, Cnr = -0.20, Cnb = 0.09, Clb = -0.12, Cmde = -0.85, Cndr = -0.055, de = 20, da = 18, dr = 25, rde = 40, rda = 55, rdr = 60,
    kx = 0.11, ky = 0.17, kz = 0.22, sb = 0.05, up = 4.5, dn = 3, ab = 0.6, vne = 336, pu = 0.1, qmax = 0.45 },
  -- 歼-8II：两台涡喷-13AII（军推各 42.7 千牛、加力 65.9 千牛），60° 三角翼 + 常规平尾，机身细长（偏航惯量大），机械操纵 + 阻尼器；
  --   截击机：高速好、转弯差（翼载大、三角翼诱导阻力大）
  j8 = { m0 = 9820, fi = 4330, S = 42.2, b = 9.34, c = 5.0, L = 21.59, Tm = 85300, Ta = 131800,
    CLa = 2.9, aS = 28, CLm = 1.15, CD0 = 0.019, e = 0.7, Mcr = 0.9, CDw = 0.042, nz = { -3, 7.5 }, pmax = 150, fcs = "mech", bw = 0.55, sm = 0.06,
    Cmq = -4.5, Clp = -0.22, Cnr = -0.32, Cnb = 0.12, Clb = -0.08, Cmde = -0.8, Cndr = -0.07, de = 22, da = 20, dr = 25, rde = 40, rda = 55, rdr = 60,
    kx = 0.095, ky = 0.18, kz = 0.23, sb = 0.06, up = 4.5, dn = 3, ab = 0.6, vne = 361, Kq = 0.15, Kr = 0.3, qmax = 0.4 },
  -- 歼-10C：单台涡扇-10B（军推约 86 千牛、加力约 138 千牛，外界估算），鸭式三角翼，放宽静稳定 + 数字电传；轻、灵，滚转快
  j10 = { m0 = 9750, fi = 3800, S = 33.1, b = 9.75, c = 5.0, L = 16.9, Tm = 86000, Ta = 138000, ne = 1,
    CLa = 3.3, aS = 35, CLm = 1.75, CD0 = 0.0185, e = 0.9, Mcr = 0.88, CDw = 0.03, nz = { -3, 9 }, aL = 28, pmax = 280, bw = 1.15, tn = 0.14, tp = 0.11, sm = -0.06,
    Cmq = -4.2, Clp = -0.26, Cnr = -0.28, Cnb = 0.11, Clb = -0.07, Cmde = -0.6, Cndr = -0.065, de = 25, da = 25, dr = 30, rde = 65, rda = 110, rdr = 120,
    kx = 0.115, ky = 0.19, kz = 0.24, sb = 0.045, vne = 403, qmax = 0.55 },
  -- 歼-11B：两台涡扇-10A（军推各约 78 千牛、加力 132 千牛），苏-27 的布局：边条 + 自动前缘襟翼（最大升力系数高）、俯仰模拟电传（带迎角限制 26°）；
  --   重（满内油 9.4 吨），滚转惯量大
  j11 = { m0 = 16500, fi = 9400, S = 62, b = 14.7, c = 3.85, L = 21.9, Tm = 156000, Ta = 264000,
    CLa = 3.4, aS = 33, CLm = 1.95, CD0 = 0.0205, e = 0.78, Mcr = 0.88, CDw = 0.03, nz = { -3, 9 }, aL = 26, pmax = 270, bw = 0.9, tn = 0.18, tp = 0.13, sm = -0.05,
    Cmq = -5.5, Clp = -0.28, Cnr = -0.3, Cnb = 0.11, Clb = -0.07, Cmde = -0.8, Cndr = -0.06, de = 25, da = 20, dr = 25, rde = 60, rda = 75, rdr = 90,
    kx = 0.12, ky = 0.18, kz = 0.23, sb = 0.07, up = 4, dn = 3, ab = 0.5, vne = 389, qmax = 0.5 },
  -- 歼-15T：苏-33 的布局（鸭翼、加大的机翼和双缝襟翼，舰载），两台涡扇-10H（加力约 135 千牛，外界估算），数字电传；比歼-11 重、低速升力好
  j15t = { m0 = 17500, fi = 9500, S = 67.84, b = 14.7, c = 3.95, L = 21.9, Tm = 160000, Ta = 270000,
    CLa = 3.4, aS = 34, CLm = 2.0, CD0 = 0.0225, e = 0.78, Mcr = 0.88, CDw = 0.032, nz = { -3, 8.5 }, aL = 28, pmax = 230, bw = 0.9, tn = 0.18, tp = 0.13, sm = -0.04,
    Cmq = -5.5, Clp = -0.28, Cnr = -0.3, Cnb = 0.11, Clb = -0.07, Cmde = -0.85, Cndr = -0.06, da = 20, dr = 25, rde = 60, rda = 75, rdr = 90,
    kx = 0.125, ky = 0.18, kz = 0.23, sb = 0.07, up = 4, dn = 3, ab = 0.5, vne = 361, flapCL = 0.45, qmax = 0.48 },
  -- 歼-16：苏-30MKK 的路子（双座、加强结构），两台涡扇-10A，数字电传；重、挂点多，过载 8.5 g
  j16 = { m0 = 17700, fi = 9600, S = 62, b = 14.7, c = 3.85, L = 21.9, Tm = 156000, Ta = 264000,
    CLa = 3.4, aS = 33, CLm = 1.9, CD0 = 0.0225, e = 0.78, Mcr = 0.88, CDw = 0.032, nz = { -3, 8.5 }, aL = 26, pmax = 240, bw = 0.9, tn = 0.18, tp = 0.13, sm = -0.05,
    Cmq = -5.5, Clp = -0.28, Cnr = -0.3, Cnb = 0.11, Clb = -0.07, Cmde = -0.8, Cndr = -0.06, da = 20, dr = 25, rde = 60, rda = 75, rdr = 90,
    kx = 0.122, ky = 0.18, kz = 0.23, sb = 0.07, up = 4, dn = 3, ab = 0.5, vne = 375, qmax = 0.48 },
  -- 歼-20：鸭翼 + 三角翼 + 边条，两台涡扇-10C（军推各约 90 千牛、加力约 142 千牛）；空重约 19.5 吨、内油约 11 吨（外界估算）；
  --   全动鸭翼、全动垂尾，放宽静稳定很多（sm −0.08）+ 数字电传；弹舱内挂，零升阻力低
  j20 = { m0 = 19500, fi = 11000, S = 73, b = 13.0, c = 6.8, L = 20.4, Tm = 180000, Ta = 284000,
    CLa = 3.2, aS = 38, CLm = 1.9, CD0 = 0.0185, e = 0.95, Mcr = 0.9, CDw = 0.03, nz = { -3, 9 }, aL = 30, pmax = 250, bw = 1.05, tn = 0.15, tp = 0.12, sm = -0.08,
    Cmq = -4.5, Clp = -0.24, Cnr = -0.25, Cnb = 0.09, Clb = -0.06, Cmde = -0.6, Cndr = -0.07, de = 30, da = 25, dr = 25, rde = 70, rda = 110, rdr = 100,
    kx = 0.115, ky = 0.18, kz = 0.23, sb = 0.05, up = 4, dn = 3, ab = 0.45, vne = 403, qmax = 0.52 },
  -- 歼-35（舰载）：两台涡扇-19（军推各约 72 千牛、加力约 116 千牛），空重约 16 吨、翼面积约 50 平方米（外界估算）
  j35 = { m0 = 16000, fi = 8500, S = 50, b = 11.5, c = 5.0, L = 17.3, Tm = 144000, Ta = 232000,
    CLa = 3.3, aS = 35, CLm = 1.75, CD0 = 0.0195, e = 0.9, Mcr = 0.88, CDw = 0.038, nz = { -3, 9 }, aL = 30, pmax = 240, bw = 1.05, tn = 0.15, tp = 0.12, sm = -0.05,
    Cmq = -5, Clp = -0.28, Cnr = -0.28, Cnb = 0.1, Clb = -0.07, Cmde = -0.75, Cndr = -0.065,
    kx = 0.115, ky = 0.18, kz = 0.235, sb = 0.045, vne = 389, flapCL = 0.4, qmax = 0.53 },
  -- 歼-36：无尾飞翼（没有垂尾：航向静稳定几乎是零，靠电传用开裂式阻力舵管偏航）、三台发动机（各按加力 142 千牛估）；
  --   一切按外界估算：空重约 30 吨、翼面积约 190 平方米（翼载低、展弦比小）
  j36 = { m0 = 30000, fi = 16000, S = 190, b = 20.0, c = 11.0, L = 23.0, Tm = 270000, Ta = 426000, ne = 3,
    CLa = 2.8, aS = 30, CLm = 1.3, CD0 = 0.012, e = 0.85, Mcr = 0.9, CDw = 0.028, nz = { -3, 7.5 }, aL = 24, pmax = 160, bw = 0.8, tn = 0.22, tp = 0.16, sm = -0.01,
    Cmq = -2.5, Clp = -0.28, Cnr = -0.06, Cnb = 0.01, Clb = -0.05, Cmde = -0.35, Cndr = -0.04, de = 30, da = 30, dr = 40, rde = 60, rda = 70, rdr = 80,
    kx = 0.16, ky = 0.2, kz = 0.25, sb = 0.06, vne = 403, qmax = 0.4 },
  -- 轰-6K：两台 D-30KP-2 涡扇（各 118 千牛，不加力），35° 后掠大展弦比翼；机械操纵 + 自动驾驶的阻尼器；重、惯量大，滚转一秒二三十度
  h6k = { m0 = 38000, fi = 30000, S = 165, b = 33.0, c = 5.6, L = 34.8, Tm = 236000, lap = { 0.35, 0.1 },
    CLa = 4.4, aS = 16, CLm = 1.35, CD0 = 0.023, e = 0.8, Mcr = 0.78, CDw = 0.03, nz = { -1, 2.5 }, pmax = 30, fcs = "mech", bw = 0.4, sm = 0.12,
    Cmq = -18, Clp = -0.45, Cnr = -0.25, Cnb = 0.1, Clb = -0.1, Cmde = -1.6, Cndr = -0.1, de = 20, da = 18, dr = 25, rde = 25, rda = 30, rdr = 30,
    kx = 0.14, ky = 0.17, kz = 0.2, sb = 0.03, up = 6, dn = 4, vne = 270, Kq = 0.4, Kr = 0.6, flapCL = 0.6, qmax = 0.12, tn = 0.4, tp = 0.3 },
  -- 攻击-11：飞翼无人机（单台不加力涡扇，约 55 千牛，外界估算）；没有垂尾，航向几乎没有静稳定，电传管着
  gj11 = { m0 = 6500, fi = 2500, S = 45, b = 14.0, c = 4.0, L = 10.0, Tm = 55000, ne = 1, lap = { 0.25, 0.1 },
    CLa = 3.5, aS = 22, CLm = 1.0, CD0 = 0.012, e = 0.85, Mcr = 0.78, CDw = 0.03, nz = { -2, 6 }, aL = 18, pmax = 120, bw = 0.8, tn = 0.2, tp = 0.15, sm = -0.01,
    Cmq = -2.0, Clp = -0.25, Cnr = -0.05, Cnb = 0.01, Clb = -0.05, Cmde = -0.35, Cndr = -0.04, de = 30, da = 30, dr = 40,
    kx = 0.14, ky = 0.2, kz = 0.24, sb = 0.05, up = 4, vne = 290, qmax = 0.4 },
  -- 翼龙-2：涡桨（约 500 千瓦），20.5 米大展弦比直翼；自动驾驶飞
  gj2 = { m0 = 2300, fi = 1300, S = 20.5, b = 20.5, c = 1.0, L = 11.0, ne = 1, prop = { P = 500e3, Tst = 7500, eta = 0.8 },
    CLa = 5.5, aS = 15, CLm = 1.4, CD0 = 0.024, e = 0.85, Mcr = 0.6, CDw = 0.02, nz = { -1.5, 3 }, aL = 12, pmax = 45, bw = 0.5, tn = 0.3, tp = 0.2, sm = 0.1,
    Cmq = -12, Clp = -0.6, Cnr = -0.15, Cnb = 0.06, Clb = -0.1, Cmde = -1.4, Cndr = -0.06, de = 25, da = 25, dr = 25, rde = 40, rda = 50, rdr = 50,
    kx = 0.17, ky = 0.17, kz = 0.22, sb = 0, up = 4, dn = 3, vne = 125, gearCD = 0.015, flapCL = 0.4, qmax = 0.2 },

  -- —— 美军 ——
  -- A-10C：两台 TF34（各 40.3 千牛，高涵道比：推力随速度掉得多），17.5 米平直翼（诱导阻力小、低速转得急、滚转阻尼大），厚翼型阻力发散早；
  --   机械操纵（液压，带偏航增稳），很稳；开裂式副翼当减速板，减速极猛
  a10c = { m0 = 11321, fi = 4853, S = 47.0, b = 17.53, c = 2.73, L = 16.26, Tm = 80600, lap = { 0.55, 0.12 },
    CLa = 4.8, aS = 18, CLm = 1.6, CD0 = 0.037, e = 0.8, Mcr = 0.55, CDw = 0.045, nz = { -3, 7.33 }, pmax = 120, fcs = "mech", bw = 0.55, sm = 0.12,
    Cmq = -14, Clp = -0.5, Cnr = -0.2, Cnb = 0.09, Clb = -0.1, Cmde = -1.5, Cndr = -0.09, de = 25, da = 25, dr = 25, rde = 40, rda = 60, rdr = 60,
    kx = 0.14, ky = 0.18, kz = 0.22, sb = 0.12, up = 6, dn = 4, vne = 231, Kq = 0.1, Kr = 0.5, flapCL = 0.45, qmax = 0.35 },
  -- B-2A：四台 F118（各 77 千牛，不加力），飞翼（没有垂尾，靠开裂式阻力舵管偏航），四余度电传；滚转惯量极大
  b2 = { m0 = 71700, fi = 75750, S = 478, b = 52.4, c = 12.0, L = 21.0, Tm = 308000, ne = 4, lap = { 0.25, 0.1 },
    CLa = 3.9, aS = 18, CLm = 0.95, CD0 = 0.012, e = 0.9, Mcr = 0.82, CDw = 0.025, nz = { -1, 2.5 }, aL = 14, pmax = 35, bw = 0.6, tn = 0.3, tp = 0.25, sm = -0.01,
    Cmq = -1.8, Clp = -0.4, Cnr = -0.04, Cnb = 0.005, Clb = -0.04, Cmde = -0.3, Cndr = -0.03, de = 30, da = 30, dr = 45, rde = 40, rda = 50, rdr = 60,
    kx = 0.2, ky = 0.25, kz = 0.319, sb = 0.04, up = 6, dn = 4, vne = 260, qmax = 0.12 },
  -- F-14A：两台 TF30-P-414A（军推各 54.9 千牛、加力 93 千牛，出了名的软、转速起来慢），变后掠翼（20° ~ 68°，中央大气数据计算机按马赫数自动调）：
  --   翼展、升力线斜率、最大升力、阻力发散、滚转阻尼都跟着后掠角变（swp）；机械 + 增稳，扰流板 + 差动平尾滚转
  f14 = { m0 = 18191, fi = 7348, S = 52.49, b = 19.54, c = 2.99, L = 19.1, Tm = 109800, Ta = 186000,
    CLa = 4.6, aS = 24, CLm = 1.9, CD0 = 0.021, e = 0.62, Mcr = 0.78, CDw = 0.04, nz = { -3, 7.5 }, pmax = 160, fcs = "cas", bw = 0.65, tn = 0.25, tp = 0.18, sm = 0.05,
    Cmq = -6.5, Clp = -0.45, Cnr = -0.32, Cnb = 0.12, Clb = -0.12, Cmde = -0.9, Cndr = -0.07, de = 30, da = 20, dr = 30, rde = 50, rda = 60, rdr = 80,
    kx = 0.13, ky = 0.18, kz = 0.23, sb = 0.07, up = 5, dn = 3.5, ab = 0.7, vne = 411, qmax = 0.45,
    swp = { M0 = 0.55, M1 = 0.95, b = 11.65, CLa = 3.0, CLm = 1.25, aS = 28, Mcr = 0.95, CDw = 0.024, Clp = -0.25, kx = 0.1 } },
  -- F-15C：两台 F100-PW-220（军推各 64.9 千牛、加力 105.7 千牛），翼面积大（翼载低、瞬时转弯好）、没有前缘装置；机械 + 控制增强（CAS），稳定；
  --   背上大减速板
  f15 = { m0 = 12700, fi = 6100, S = 56.5, b = 13.05, c = 4.86, L = 19.43, Tm = 129800, Ta = 211400,
    CLa = 3.4, aS = 30, CLm = 1.35, CD0 = 0.0195, e = 0.72, Mcr = 0.88, CDw = 0.03, nz = { -3, 9 }, pmax = 220, fcs = "cas", bw = 0.8, tn = 0.2, tp = 0.14, sm = 0.03,
    Cmq = -6.5, Clp = -0.32, Cnr = -0.3, Cnb = 0.11, Clb = -0.07, Cmde = -0.85, Cndr = -0.065, de = 29, da = 20, dr = 30, rde = 46, rda = 60, rdr = 100,
    kx = 0.1, ky = 0.173, kz = 0.219, sb = 0.085, up = 4, dn = 3, ab = 0.5, vne = 411, qmax = 0.5 },
  -- F-16C Block 50：一台 F110-GE-129（军推 76.3 千牛、加力 131.6 千牛），边条翼，放宽静稳定（sm −0.05）+ 电传（迎角限制 25°、滚转限 300°/s）；
  --   转动惯量照 Stevens & Lewis 的 F-16 模型（9.3 吨时 Ixx 12875、Iyy 75674、Izz 85552 kg·m²）标定回转半径；气动导数也照它的量级
  f16 = { m0 = 8570, fi = 3175, S = 27.87, b = 9.96, c = 3.45, L = 15.06, Tm = 76300, Ta = 131600, ne = 1,
    CLa = 3.6, aS = 32, CLm = 1.6, CD0 = 0.0175, e = 0.8, Mcr = 0.86, CDw = 0.042, nz = { -3, 9 }, aL = 25, pmax = 300, bw = 1.15, tn = 0.13, tp = 0.1, sm = -0.05,
    Cmq = -5.0, Clp = -0.33, Cnr = -0.32, Cnb = 0.1, Clb = -0.09, Cmde = -0.75, Cndr = -0.07, de = 25, da = 21.5, dr = 30, rde = 60, rda = 110, rdr = 120,
    kx = 0.129, ky = 0.19, kz = 0.251, sb = 0.045, vne = 411, qmax = 0.55 },
  -- F-22A：两台 F119（军推各约 116 千牛、加力 156 千牛：不开加力就能超音速巡航），二元推力矢量喷口（俯仰 ±20°），数字电传、能飞大迎角
  f22 = { m0 = 19700, fi = 8200, S = 78.04, b = 13.56, c = 6.3, L = 18.92, Tm = 232000, Ta = 312000,
    CLa = 3.2, aS = 38, CLm = 1.8, CD0 = 0.0175, e = 0.95, Mcr = 0.92, CDw = 0.032, nz = { -3, 9 }, aL = 40, pmax = 260, bw = 1.1, tn = 0.14, tp = 0.11, sm = -0.04,
    Cmq = -6, Clp = -0.3, Cnr = -0.28, Cnb = 0.13, Clb = -0.08, Cmde = -0.8, Cndr = -0.06, de = 25, da = 25, dr = 30, rde = 65, rda = 120, rdr = 120,
    kx = 0.11, ky = 0.18, kz = 0.23, sb = 0.05, vne = 411, tvc = { p = 20, y = 0, r = 45 }, qmax = 0.6 },
  -- F-35A：一台 F135（军推约 128 千牛、加力 191 千牛），机身胖、翼载大：持续转弯差（诱导阻力因子按美国国防部试验鉴定局报告的持续转弯反推）、
  --   跨声速阻力大；数字电传，迎角能到 50°（限制按 35° 给）
  f35 = { m0 = 13290, fi = 8278, S = 42.7, b = 10.7, c = 4.58, L = 15.67, Tm = 128000, Ta = 191000, ne = 1,
    CLa = 3.3, aS = 35, CLm = 1.6, CD0 = 0.022, K = 0.16, Mcr = 0.82, CDw = 0.042, nz = { -3, 9 }, aL = 35, pmax = 220, bw = 1.05, tn = 0.15, tp = 0.12, sm = -0.03,
    Cmq = -5, Clp = -0.3, Cnr = -0.28, Cnb = 0.1, Clb = -0.07, Cmde = -0.85, Cndr = -0.06,
    kx = 0.115, ky = 0.18, kz = 0.235, sb = 0.04, vne = 372, qmax = 0.5 },
  -- MQ-9A：TPE331-10 涡桨（712 千瓦），20 米大展弦比翼，V 形尾；自动驾驶飞
  mq9 = { m0 = 2223, fi = 1800, S = 22.0, b = 20.1, c = 1.12, L = 11.0, ne = 1, prop = { P = 712e3, Tst = 9500, eta = 0.8 },
    CLa = 5.5, aS = 15, CLm = 1.4, CD0 = 0.024, e = 0.85, Mcr = 0.6, CDw = 0.02, nz = { -1.5, 3 }, aL = 12, pmax = 40, bw = 0.5, tn = 0.3, tp = 0.2, sm = 0.1,
    Cmq = -12, Clp = -0.6, Cnr = -0.15, Cnb = 0.06, Clb = -0.1, Cmde = -1.4, Cndr = -0.06, de = 25, da = 25, dr = 25, rde = 40, rda = 50, rdr = 50,
    kx = 0.17, ky = 0.17, kz = 0.22, sb = 0, up = 4, dn = 3, vne = 140, gearCD = 0.015, flapCL = 0.4, qmax = 0.2 },

  -- —— 俄军 ——
  -- 米格-29（9.12）：两台 RD-33（军推各 49.4 千牛、加力 81.4 千牛，转速起得快），边条翼；液压机械操纵 + 增稳（SAU-451）+ 迎角限制器 26°，
  --   亚音速时略微静不稳定；轻、推重比高、瞬时转弯好
  mig29 = { m0 = 11000, fi = 3430, S = 38.0, b = 11.36, c = 3.73, L = 17.32, Tm = 98800, Ta = 162800,
    CLa = 3.6, aS = 32, CLm = 1.85, CD0 = 0.0205, e = 0.78, Mcr = 0.87, CDw = 0.032, nz = { -3, 9 }, aL = 26, pmax = 200, fcs = "cas", bw = 0.75, tn = 0.18, tp = 0.14, sm = -0.02,
    Cmq = -6, Clp = -0.3, Cnr = -0.32, Cnb = 0.12, Clb = -0.08, Cmde = -0.85, Cndr = -0.06, da = 20, dr = 25, rde = 45, rda = 60, rdr = 80,
    kx = 0.11, ky = 0.18, kz = 0.23, sb = 0.06, up = 3, dn = 2.5, ab = 0.35, vne = 417, qmax = 0.55 },
  -- 苏-27（苏-27S）：两台 AL-31F（军推各 74.5 千牛、加力 122.6 千牛），俯仰模拟电传（SDU-10，迎角限制 26°），滚转 / 偏航机械 + 增稳
  su27 = { m0 = 16380, fi = 9400, S = 62, b = 14.7, c = 3.85, L = 21.9, Tm = 149000, Ta = 245200,
    CLa = 3.4, aS = 33, CLm = 1.95, CD0 = 0.0205, e = 0.78, Mcr = 0.88, CDw = 0.03, nz = { -3, 9 }, aL = 26, pmax = 270, bw = 0.85, tn = 0.18, tp = 0.13, sm = -0.05,
    Cmq = -5.5, Clp = -0.28, Cnr = -0.3, Cnb = 0.11, Clb = -0.07, Cmde = -0.8, Cndr = -0.06, da = 20, dr = 25, rde = 60, rda = 75, rdr = 90,
    kx = 0.12, ky = 0.18, kz = 0.23, sb = 0.07, up = 4, dn = 3, ab = 0.5, vne = 389, qmax = 0.5 },
  -- 苏-35S：两台 AL-41F1S（117S：军推各 86.3 千牛、加力 142.2 千牛），喷口在外倾 32° 的斜面里偏 ±15°（俯仰 + 偏航），数字电传 KSU-35；
  --   没有鸭翼、减速板改成全动垂尾差动
  su35 = { m0 = 18400, fi = 11500, S = 62, b = 15.3, c = 3.85, L = 21.9, Tm = 172600, Ta = 284400,
    CLa = 3.5, aS = 35, CLm = 2.0, CD0 = 0.021, e = 0.82, Mcr = 0.88, CDw = 0.034, nz = { -3, 9 }, aL = 30, pmax = 280, tn = 0.16, tp = 0.12, sm = -0.05,
    Cmq = -5.5, Clp = -0.28, Cnr = -0.3, Cnb = 0.11, Clb = -0.07, Cmde = -0.8, Cndr = -0.06, rde = 60, rda = 110, rdr = 100,
    kx = 0.125, ky = 0.18, kz = 0.23, sb = 0.07, vne = 389, tvc = { p = 15, y = 8, r = 60 }, qmax = 0.55 },
  -- 苏-57：两台 AL-41F1（117：军推各约 88 千牛、加力 147 千牛），全向推力矢量（±16°）、活动边条、全动垂尾，放宽静稳定 + 数字电传，超机动
  su57 = { m0 = 18500, fi = 10300, S = 78.8, b = 14.1, c = 6.0, L = 20.1, Tm = 176600, Ta = 294200,
    CLa = 3.1, aS = 40, CLm = 2.0, CD0 = 0.0185, e = 0.9, Mcr = 0.9, CDw = 0.024, nz = { -3, 9 }, aL = 35, pmax = 290, bw = 1.05, tn = 0.14, tp = 0.11, sm = -0.07,
    Cmq = -5, Clp = -0.27, Cnr = -0.28, Cnb = 0.1, Clb = -0.06, Cmde = -0.75, Cndr = -0.07, rde = 65, rda = 120, rdr = 120,
    kx = 0.12, ky = 0.18, kz = 0.23, sb = 0.05, vne = 389, tvc = { p = 16, y = 16, r = 60 }, qmax = 0.6 },
  -- 苏-25：两台 R-95Sh 涡喷（各 40.2 千牛，不加力；涡喷推力不怎么随速度掉），大展弦比直翼 + 前缘缝翼；机械操纵（助力）+ 阻尼器，稳；
  --   翼尖开裂式减速板
  su25 = { m0 = 9500, fi = 3000, S = 30.1, b = 14.36, c = 2.3, L = 15.33, Tm = 80400, lap = { 0.1, 0.12 },
    CLa = 4.6, aS = 18, CLm = 1.5, CD0 = 0.03, e = 0.8, Mcr = 0.7, CDw = 0.045, nz = { -3, 6.5 }, pmax = 125, fcs = "mech", bw = 0.55, sm = 0.1,
    Cmq = -12, Clp = -0.48, Cnr = -0.22, Cnb = 0.1, Clb = -0.09, Cmde = -1.3, Cndr = -0.08, de = 25, da = 20, dr = 25, rde = 40, rda = 50, rdr = 60,
    kx = 0.14, ky = 0.18, kz = 0.22, sb = 0.12, up = 5, dn = 3.5, vne = 280, Kq = 0.1, Kr = 0.4, flapCL = 0.45, qmax = 0.35 },
}
-- T-50（苏-57 的原型机）：同样的发动机，原型机更重（测试设备），飞控软件限制保守一些
FM.AC.t50 = setmetatable({ m0 = 19000, aL = 30, pmax = 260, bw = 0.95 }, { __index = FM.AC.su57 })
-- 苏-27 系（边条 + 放宽静稳定）：失速后低头力矩小——真机不靠推力矢量也能拉眼镜蛇（苏-27，1989 年巴黎航展），解除迎角限制后能仰到 90° 以上
for _, k in ipairs({ "j11", "j15t", "j16", "su27", "su35", "su57" }) do FM.AC[k].cmS = 0.1 end

-- 同型号不同版本（科技树的键：用户 11-26「同型号不同版本分开……自己的性能」）：照 base 那一型，改写不一样的量
FM.VAR = {
  us_f16a = { base = "f16", m0 = 7070, fi = 3160, Tm = 64900, Ta = 106000, bw = 1.05 },   -- F-16A Block 10/15：F100-PW-200（军推 64.9、加力 106 千牛），模拟电传
  jp_f2a = { base = "f16", m0 = 9527, fi = 3700, S = 34.84, b = 11.13, c = 3.6, L = 15.52, Tm = 76000, Ta = 131000, CD0 = 0.0185, pmax = 280, bw = 1.1, kx = 0.135, aL = 26 },   -- F-2A：机翼放大 25%，F110-IHI-129
  us_f15a = { base = "f15", m0 = 12250, fi = 5260, Tm = 130600, Ta = 212000 },   -- F-15A：F100-PW-100
  us_f15e = { base = "f15", m0 = 14300, fi = 10400, CD0 = 0.025, Tm = 158000, Ta = 259400, pmax = 200, kx = 0.105 },   -- F-15E：保形油箱（算进内油）、F100-PW-229
  jp_f15jm = { base = "f15" },   -- F-15J（M）：F100-IHI-220E，同 F-15C
  us_a10a = { base = "a10c", m0 = 11000 },
  cn_j10a = { base = "j10", Tm = 76000, Ta = 123000, bw = 1.1, pmax = 270 },   -- 歼-10A：AL-31FN
  cn_j11 = { base = "j11", m0 = 16380, Tm = 149000, Ta = 245200 },   -- 歼-11（早期）：AL-31F
  ru_su27sm = { base = "su27", m0 = 16600, Tm = 152000, Ta = 264000, bw = 0.9 },   -- 苏-27SM：AL-31F-M1
  -- 苏-30SM：鸭翼 + 推力矢量（AL-31FP，喷口在外倾 32° 的斜面里偏 ±15°），数字电传；用歼-16 的模型
  ru_su30sm = { base = "j16", m0 = 18800, fi = 9640, Tm = 150000, Ta = 245200, CLm = 2.0, aS = 35, aL = 30, pmax = 230, bw = 0.95, nz = { -3, 9 },
    tvc = { p = 15, y = 8, r = 60 } },
}

---------------------------------------------------------------- 推导

local cache = {}
-- 这一型（科技树的键优先）的物理量：缺的按 BASE，换算成弧度、算转动惯量的回转半径、诱导阻力因子、副翼操纵导数……
function FM.get(id, treeKey)
  local key = (treeKey and FM.VAR[treeKey]) and treeKey or id
  if cache[key] then return cache[key] end
  local src
  if FM.VAR[key] then
    local v = FM.VAR[key]
    src = setmetatable({}, { __index = function(_, k) if v[k] ~= nil then return v[k] end return FM.AC[v.base][k] end })
  else
    src = FM.AC[key]
  end
  if not src then return nil end
  local D = { key = key }
  for k, v in pairs(BASE) do D[k] = v end
  local fields = { "m0", "fi", "S", "b", "c", "L", "Tm", "Ta", "ne", "lap", "CLa", "aS", "CLm", "CD0", "e", "K", "Mcr", "CDw", "nz", "aL", "pmax", "fcs", "bw", "tn", "tp", "sm",
    "Cm0", "Cmq", "Clp", "Cnr", "Cnb", "Clb", "CYb", "Clr", "Cnp", "Cmde", "Clda", "Cndr", "CYdr", "Cnda", "Cldr", "de", "da", "dr", "rde", "rda", "rdr",
    "kx", "ky", "kz", "sb", "gearCD", "flapCL", "up", "dn", "ab", "vne", "Kq", "Kr", "qmax", "pu", "tvc", "prop", "swp", "cmS" }
  for _, f in ipairs(fields) do
    local v = src[f]
    if v ~= nil then D[f] = v end
  end
  -- 前置滤波按操纵方式给默认：电传脆、增稳次之、机械（教官飞的时候）最慢
  -- 11-28 用户「有时候不该灵敏的时候过于灵敏 该灵敏的时候又有点迟钝」：原来 0.16 / 0.12 秒（电传）、0.22 / 0.16（增稳）、0.3 / 0.22（机械）——
  --   加上键盘推杆、低速时跟得慢的增益，按住半秒才拉起一两个 g；收快三四成（kbfeel.lua 量的）
  D.tn = D.tn or ((D.fcs == "fbw") and 0.1 or ((D.fcs == "cas") and 0.14 or 0.2))
  D.tp = D.tp or ((D.fcs == "fbw") and 0.08 or ((D.fcs == "cas") and 0.11 or 0.15))
  if D.prop and not D.Tm then D.Tm = D.prop.Tst end
  D.Ta = D.Ta or D.Tm
  D.vne = D.vne or 400
  D.CLa, D.CLm = D.CLa * AGILE.lift, D.CLm * AGILE.lift   -- 转弯机动性（见上面 AGILE）
  if D.K then D.K = D.K * AGILE.ind else D.e = D.e / AGILE.ind end
  FM.finish(D)
  cache[key] = D
  return D
end

-- 跟后掠角、换算有关的量（F-14 后掠变了要重算一遍：FM.sweep）
function FM.finish(D)
  D.AR = D.b * D.b / D.S
  D.Kc = D.K or 1 / (math.pi * D.AR * D.e)
  D.aSr = D.aS * RAD
  D.aLr = D.aL and D.aL * RAD or nil
  D.pmaxr = D.pmax * RAD
  D.der, D.dar, D.drr = D.de * RAD, D.da * RAD, D.dr * RAD
  D.rder, D.rdar, D.rdrr = D.rde * RAD, D.rda * RAD, D.rdr * RAD
  D.Cma = -D.CLa * D.sm
  -- 升力曲线：线性段到 a1，之后二次曲线圆滑到失速迎角处的最大升力（斜率连续）
  local aLin = D.CLm / D.CLa
  local a1 = 2 * aLin - D.aSr
  if a1 < 0.5 * aLin or a1 >= D.aSr then a1 = 0.75 * D.aSr end
  D.a1 = a1
  D.CL1 = D.CLa * a1
  -- 负迎角：失速得早、最大升力小
  D.aSN, D.CLmN = D.aSr * 0.65, D.CLm * 0.6
  D.a1N = math.min(D.aSN * 0.75, D.CLmN / D.CLa)
  D.CL1N = D.CLa * D.a1N
  -- 回转半径（米）：转动惯量 = 质量 × 半径²
  D.rx2 = (D.kx * D.b) ^ 2
  D.ry2 = (D.ky * D.L) ^ 2
  D.rz2 = (D.kz * (D.b + D.L) / 2) ^ 2
  D.tl = 0.42 * D.L   -- 喷口到重心
  -- 副翼操纵导数：没给的按最大滚转角速度反推——在 0.6 倍最大允许速度下，满副翼的稳态滚转角速度比 pmax 多一成五
  if not D.Clda then
    local Vr = 0.6 * D.vne
    D.Clda = abs(D.Clp) * (D.pmaxr * D.b / (2 * Vr)) / D.dar * 1.15
  end
  D.nzN, D.nzP = D.nz[1], D.nz[2]
  return D
end

-- F-14：按马赫数自动调后掠角（0 ~ 1：20° ~ 68°），返回这一刻的量（缓存两档之间插值的那张表，按 0.02 一档）
local swCache = {}
function FM.sweep(D, M)
  local W = D.swp
  if not W then return D, 0 end
  local s = smooth(W.M0, W.M1, M)
  local k = math.floor(s * 50 + 0.5)
  local ck = D.key .. "@" .. k
  local E = swCache[ck]
  if not E then
    local t = k / 50
    E = setmetatable({}, { __index = D })
    E.b = lerp(D.b, W.b, t)
    E.CLa = lerp(D.CLa, W.CLa * AGILE.lift, t)   -- 收后掠那一套也乘转弯机动性（D 的已经在 FM.get 里乘过）
    E.CLm = lerp(D.CLm, W.CLm * AGILE.lift, t)
    E.aS = lerp(D.aS, W.aS, t)
    E.Mcr = lerp(D.Mcr, W.Mcr, t)
    E.CDw = lerp(D.CDw, W.CDw, t)
    E.Clp = lerp(D.Clp, W.Clp, t)
    E.kx = lerp(D.kx, W.kx, t)
    E.Clda = nil
    E.K = nil
    for _, f in ipairs({ "AR", "Kc", "aSr", "a1", "CL1", "aSN", "CLmN", "a1N", "CL1N", "rx2", "Cma" }) do E[f] = nil end
    FM.finish(E)
    E.Clda = D.Clda * lerp(1, 0.75, t)   -- 收起后掠：扰流板 + 差动平尾的滚转力矩小一些
    E.sweepK = t
    swCache[ck] = E
  end
  return E, E.sweepK
end

---------------------------------------------------------------- 气动、推力

-- 升力系数（迎角 rad；flap 0 ~ 1）
local function CLof(D, a, flap)
  local sgn, aa = 1, a
  if a < 0 then sgn, aa = -1, -a end
  local CLm, aS, a1, CL1
  if sgn > 0 then CLm, aS, a1, CL1 = D.CLm, D.aSr, D.a1, D.CL1 else CLm, aS, a1, CL1 = D.CLmN, D.aSN, D.a1N, D.CL1N end
  local cl
  if aa <= a1 then
    cl = D.CLa * aa
  elseif aa <= aS then
    local t = (aS - aa) / (aS - a1)
    cl = CLm - (CLm - CL1) * t * t
  else
    local s = smooth(aS, aS + 0.35, aa)
    -- 失速以后按平板（1.05·sin 2α）；过了 90°（倒着来流：尾冲、库尔比特翻过去那一下）升力反过来，翼型倒着吹效率低（× 0.8）
    local plate = 1.05 * sin(2 * aa)
    if aa > math.pi / 2 then plate = plate * 0.8 end
    cl = lerp(CLm, plate, s)
  end
  local fl = (flap or 0) * D.flapCL * (1 - smooth(aS, aS + 0.3, aa))
  return cl * sgn + fl
end
FM.CL = CLof
-- 反过来：要这么大的升力系数要多大迎角（正的那一边；超过最大升力就是失速迎角）
local function CLinv(D, cl)
  if cl <= 0 then return math.max(cl / D.CLa, -D.aSN) end
  if cl <= D.CL1 then return cl / D.CLa end
  if cl >= D.CLm then return D.aSr end
  return D.aSr - (D.aSr - D.a1) * sqrt((D.CLm - cl) / (D.CLm - D.CL1))
end
FM.CLinv = CLinv

-- 跨声速 / 超音速波阻的形状：过了阻力发散马赫数往上冲，过了 1.2 马赫慢慢回落三成
local function waveK(D, M)
  return smooth(D.Mcr, D.Mcr + 0.2, M) * (1 - 0.3 * smooth(1.2, 1.8, M))
end
FM.waveK = waveK

-- 推力（N）：转速 N（军推的几成）、加力 ab（0 ~ 1）、马赫数、密度、真速
local function thrustOf(D, N, ab, M, rho, V)
  local dens = (rho / 1.225) ^ 0.75
  if D.prop then
    local P = D.prop
    local T = math.min(P.Tst, P.eta * P.P / math.max(V, 1)) * (0.05 + 0.95 * N)
    return T * dens
  end
  local lap = D.lap
  local fm = 1 - lap[1] * M + lap[2] * M * M
  local fa = 1 - 0.05 * M + 0.15 * M * M
  local T = D.Tm * (0.05 + 0.95 * N) * fm
  if ab > 0 and D.Ta > D.Tm then T = T + (D.Ta * fa - D.Tm * fm) * ab end
  return T * dens
end
FM.thrust = thrustOf

-- 外挂的质量（kg）、阻力面积（m²：迎风面积 × 0.35 + 挂架 0.01）——按弹的外形（AirDefs.W 的 shape：L 长、d 直径，格）估：
--   弹体按密度 1600 kg/m³ 的圆柱算（AIM-9X 约 90 kg、霹雳-15 约 210 kg、500 公斤级炸弹约 500 kg，跟真的差不多）；副油箱另算（油在 fuelX 里）
function FM.storeMass(w, M)
  M = M or 2.8
  local sh = w and w.shape
  if not sh then return (w and w.kind == "tank") and 140 or 120 end
  local L, d = (sh.L or 8) / M, (sh.d or 0.5) / M
  if w.kind == "tank" then return 60 + 120 * d * L / 5 end   -- 空油箱的壳
  return clamp(1600 * math.pi * (d / 2) ^ 2 * L, 30, 2500)
end
function FM.storeDrag(w, M)
  M = M or 2.8
  local sh = w and w.shape
  local d = sh and (sh.d or 0.5) / M or 0.3
  return 0.35 * math.pi * (d / 2) ^ 2 + 0.01
end

-- 一套挂载的重量和阻力（开飞机 Fly.lua、机库整备的性能对比、资料卡都用这一个，不另编数）：
--   d 是 AirDefs 的型号（d.st 挂点），load 每个挂点挂什么（同 AirDefs.presetLoad，false 是空），fuel 内油几成（0～1，默认满）
--   o（可选）：D 飞行物理量（默认 FM.get(d.id, o.key)，没登记的借 d.like）、stores 每个挂点还剩几枚（默认挂满：AD.count）、
--     fuelX 副油箱里的油（按内油的几成，默认副油箱加满：AD.tankFuel）、AD（AirDefs 模块：FM 本身不 require 它——它反过来要 FM；Lune 里跑要传）
--   每个挂点：弹 / 副油箱的壳按外形估的重量（FM.storeMass）× 枚数；火箭巢一个挂点一个巢（空巢壳四成 + 剩下的火箭按发数折）；
--     阻力面积（FM.storeDrag）只算外挂，弹舱里的不算；火箭巢打空了巢还挂着、照算阻力
--   返回 { m 总重 kg（空重 + 内油 + 副油箱里的油 + 外挂）, ext 外挂重 kg（弹、巢、副油箱的壳，不含油）, xf 副油箱里的油 kg,
--     dS 外挂阻力面积 m², dCD0 零升阻力系数增量（dS / 翼面积）, fuelX, D }；没有飞行物理量（直升机、没登记的）D、m、dCD0 是 nil
local ADlazy = nil
local function airDefs(o)
  if o and o.AD then return o.AD end
  if ADlazy == nil then
    local ok, m = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("AirDefs", 5)) end)
    ADlazy = (ok and type(m) == "table") and m or false
  end
  return ADlazy or nil
end
function FM.loadout(d, load, fuel, o)
  o = o or {}
  local AD = airDefs(o)
  local D = o.D or (d and (FM.get(d.id, o.key) or (d.like and FM.get(d.like)))) or nil
  local W = AD and AD.W or {}
  local Mst = (AD and AD.M) or 2.8
  local fuelX = o.fuelX
  if fuelX == nil then fuelX = (AD and AD.tankFuel and d) and (AD.tankFuel(d, load)) or 0 end
  local fi = D and D.fi or 0
  -- 同 Fly.lua 原来的 fmMass：先空重 + 内油 + 副油箱的油，再一个挂点一个挂点加（加的顺序一样，结果一位不差）
  local m = D and (D.m0 + fi * clamp(fuel or 1, 0, 1) + fi * math.max(fuelX or 0, 0)) or 0
  local ext, dS = 0, 0
  for i, s in ipairs((d and d.st) or {}) do
    local wid = load and load[i]
    local w = wid and W[wid]
    local n
    if o.stores then n = o.stores[i] or 0 else n = (w and AD and AD.count(s, wid)) or 0 end
    if w and w.kind == "rkt" then
      local full = math.max(w.tubes or 1, 1)
      local mm = FM.storeMass(w, Mst) * (0.4 + 0.6 * clamp(n / full, 0, 1))
      m += mm
      ext += mm
      if not s.bay then dS += FM.storeDrag(w, Mst) end
    elseif w and n > 0 then
      local mm = FM.storeMass(w, Mst) * n
      m += mm
      ext += mm
      if not s.bay then dS += FM.storeDrag(w, Mst) * n end
    end
  end
  return { m = D and m or nil, ext = ext, xf = fi * math.max(fuelX or 0, 0), dS = dS, dCD0 = D and dS / D.S or nil, fuelX = fuelX, D = D }
end

---------------------------------------------------------------- 状态

-- 四元数（w, x, y, z）：机体（Roblox 局部：X 右、Y 上、Z 后）→ 世界；从旋转矩阵（CFrame:GetComponents 的 R00 … R22）求
function FM.quat(r00, r01, r02, r10, r11, r12, r20, r21, r22)
  local tr = r00 + r11 + r22
  local w, x, y, z
  if tr > 0 then
    local s = sqrt(tr + 1) * 2
    w, x, y, z = 0.25 * s, (r21 - r12) / s, (r02 - r20) / s, (r10 - r01) / s
  elseif r00 > r11 and r00 > r22 then
    local s = sqrt(1 + r00 - r11 - r22) * 2
    w, x, y, z = (r21 - r12) / s, 0.25 * s, (r01 + r10) / s, (r02 + r20) / s
  elseif r11 > r22 then
    local s = sqrt(1 + r11 - r00 - r22) * 2
    w, x, y, z = (r02 - r20) / s, (r01 + r10) / s, 0.25 * s, (r12 + r21) / s
  else
    local s = sqrt(1 + r22 - r00 - r11) * 2
    w, x, y, z = (r10 - r01) / s, (r02 + r20) / s, (r12 + r21) / s, 0.25 * s
  end
  local n = sqrt(w * w + x * x + y * y + z * z)
  return w / n, x / n, y / n, z / n
end

-- 新的飞行状态：姿态（旋转矩阵 9 个数，同 CFrame:GetComponents 的顺序）、世界速度 m/s、油门（0 ~ 130，推力按它起步）
function FM.new(D, rot, vx, vy, vz, thr)
  local F = { abT = 0, abf = 0, flap = 0 }
  FM.reset(F, rot, vx, vy, vz)
  local t = clamp(thr or 80, 0, 130)
  F.N = math.min(t, 100) / 100
  F.abf = (t > 100 and D.Ta > D.Tm) and (t - 100) / 30 or 0
  F.abLit = F.abf > 0
  return F
end
-- 重设姿态、速度（离地、弹射离舰、服务器拉回）：角速度、舵面、滤波器从零起，发动机转速、加力、襟翼留着
function FM.reset(F, rot, vx, vy, vz, q)
  F.p, F.q, F.r = 0, q or 0, 0
  F.vx, F.vy, F.vz = vx or 0, vy or 0, vz or 0
  F.de, F.da, F.dr, F.tvp, F.tvy, F.tvr = 0, 0, 0, 0, 0, 0
  F.trim, F.qf, F.nf, F.pf, F.drop, F.stallK = nil, nil, 1, 0, 0, 0
  F.al, F.be, F.nz, F.M, F.Va, F.T = 0, 0, 1, 0, 0, F.T or 0
  F.qw, F.qx, F.qy, F.qz = FM.quat(rot[1], rot[2], rot[3], rot[4], rot[5], rot[6], rot[7], rot[8], rot[9])
end

-- 机体三轴（世界坐标）：右、上、前
function FM.axes(F)
  local w, x, y, z = F.qw, F.qx, F.qy, F.qz
  local rX, rY, rZ = 1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w)
  local uX, uY, uZ = 2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w)
  local bX, bY, bZ = 2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y)
  return rX, rY, rZ, uX, uY, uZ, -bX, -bY, -bZ
end

-- 杆的非线性：小杆量细、推满才是全量（键盘、手机摇杆都过一遍）
local function shape(s) return 0.45 * s + 0.55 * s * s * s end
FM.shape = shape

---------------------------------------------------------------- 一步

-- inp：mode "stick"（sx 压杆右正、sy 拉杆正、sz 右舵正，−1 ~ 1）/ "cmd"（n 过载、p 滚转角速度 rad/s、r 偏航角速度附加 rad/s）、
--   level 没压杆时小坡度自己改平、thr 油门 0 ~ 130、brake 减速板、gear 0 ~ 1、flap 0 ~ 1
-- env：m 质量 kg、h 高度 m、agl 离地 m（地效）、dCD0 外挂阻力系数增量、thrK 推力倍数（受伤、改装）、ctlK 舵效（受伤）、pitchK 俯仰舵效（平尾没了）、
--   liftK 升力倍数（断翼）、Lext 额外滚转力矩系数（断翼）、nzK 过载上限倍数（重了）、out 熄火、ko 飞行员昏迷
-- 返回这一帧的位移（世界坐标，米）
-- 发动机：转速往油门追（慢车 → 军推 D.up 秒），加力要转速够了、点火一下才起来（地上滑跑也调这个）
function FM.engine(F, D, dt, thr, out)
  thr = out and 0 or clamp(thr or 0, 0, 130)
  local tgt = math.min(thr, 100) / 100
  F.N = moveTo(F.N or 0, tgt, ((tgt > (F.N or 0)) and (1 / D.up) or (1 / D.dn)) * dt)
  local abW = (thr > 100 and D.Ta > D.Tm) and (thr - 100) / 30 or 0
  if abW > 0 and F.N > 0.95 then
    F.abT = (F.abT or 0) + dt
    if F.abT >= D.ab then F.abLit = true end
  else
    F.abT, F.abLit = 0, false
  end
  F.abf = moveTo(F.abf or 0, F.abLit and abW or 0, 1.6 * dt)
end

function FM.step(F, D0, dt, inp, env)
  local m = env.m
  local rho, sos = FM.atmo(env.h or 0)
  local D, sw = FM.sweep(D0, F.M or 0)
  F.sweep = sw
  FM.engine(F, D, dt, inp.thr, env.out)
  F.flap = moveTo(F.flap or 0, inp.flap or 0, dt / 2)
  local px, py, pz = 0, 0, 0
  local n = math.max(1, math.ceil(dt / FM.DT - 1e-6))
  local h = dt / n
  for _ = 1, n do
    local dx, dy, dz = FM.sub(F, D, h, inp, env, m, rho, sos)
    px, py, pz = px + dx, py + dy, pz + dz
  end
  return px, py, pz
end

-- 一小步（h ≤ 1/120 秒）
function FM.sub(F, D, h, inp, env, m, rho, sos)
  local Ixx, Iyy, Izz = m * D.rx2, m * D.ry2, m * D.rz2
  local w, x, y, z = F.qw, F.qx, F.qy, F.qz
  local rX, rY, rZ = 1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w)
  local uX, uY, uZ = 2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w)
  local bX, bY, bZ = 2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y)
  local Vx, Vy, Vz = F.vx, F.vy, F.vz
  local u = -(bX * Vx + bY * Vy + bZ * Vz)   -- 机体前向
  local v = rX * Vx + rY * Vy + rZ * Vz      -- 右
  local wd = -(uX * Vx + uY * Vy + uZ * Vz)  -- 下
  local Va = math.max(sqrt(u * u + v * v + wd * wd), 1)
  local al = atan2(wd, u)
  local be = asin(clamp(v / Va, -1, 1))
  local sbe = v / Va   -- sin β：侧滑力矩、侧力按它（小侧滑同 β；大侧滑——失速偏离、尾冲侧着飞——不再线性往上长）
  local qb = 0.5 * rho * Va * Va
  local M = Va / sos
  local p, q, r = F.p, F.q, F.r
  local Vn = math.max(Va, 40)
  local ph, qh, rh = p * D.b / (2 * Vn), q * D.c / (2 * Vn), r * D.b / (2 * Vn)
  local phi = atan2(-rY, uY)
  local th = asin(clamp(-bY, -1, 1))
  local qS = math.max(qb * D.S, 50)
  local qSc, qSb = qS * D.c, qS * D.b
  local fl = F.flap
  local ctl = env.ctlK or 1
  local aa = abs(al)
  -- 失速：迎角过了失速迎角（一边机翼先掉，方向按侧滑、没侧滑就随便一边）
  local stallK = smooth(D.aSr, D.aSr + 0.18, aa)
  if stallK > 0.05 and F.drop == 0 then
    F.drop = (be > 0.01 and -1) or (be < -0.01 and 1) or ((math.random() < 0.5) and -1 or 1)
  elseif stallK < 0.01 then
    F.drop = 0
  end
  F.stallK = stallK
  -- 失速后滚转阻尼变正：自转（尾旋的起因）——只在滚得慢时；滚快了阻尼回来（自转的转速有个头，约每秒五六十度，原来无上限，过失速时越滚越快发散）
  local fwdK = 1 - smooth(1.6, 2.2, aa)   -- 掉翼、自转只在正着来流的失速里（倒着来流——尾冲——没有）
  local Clp = D.Clp * (1 - 1.7 * stallK * fwdK * exp(-(ph / 0.15) ^ 2))
  -- 掉翼的滚转力矩随侧滑变大：对称进入（眼镜蛇、库尔比特）时小，带着侧滑失速一边机翼猛地掉下去
  local dropK = stallK * fwdK * (0.025 + 0.075 * math.min(1, abs(be) / 0.09))
  local Cnb = D.Cnb * (1 - 1.5 * smooth(D.aSr * 0.8, D.aSr * 1.3, aa))   -- 大迎角航向静稳定往下掉、变负（偏离）
  local CmSt = -D.cmS * stallK * ((al >= 0) and 1 or -1)   -- 失速后机头往下沉（倒着来流时是把机头从 180° 推开：尾冲后甩过去）
  if D.pu > 0 then CmSt = CmSt + D.pu * smooth(D.aSr * 0.75, D.aSr, aa) * (1 - stallK) * ((al >= 0) and 1 or -1) end   -- 后掠翼失速前上仰
  -- 推力（推力矢量的偏转在下面舵机那里一起动）
  local T = thrustOf(D, F.N, F.abf, M, rho, Va) * (env.thrK or 1)
  if env.out then T = 0 end
  local Tl = T * D.tl
  -- 地效：离地不到一个翼展，升力大一点、诱导阻力小一点
  local ge = env.agl and clamp(1 - env.agl / D.b, 0, 1) or 0
  local liftK = (env.liftK or 1) * (1 + 0.12 * ge * ge)
  local kInd = 1 - 0.45 * ge * ge

  ---------------------------------------------------------------- 飞控：三个舵面（和推力矢量喷口）要的偏度
  local mode = inp.mode or "stick"
  local fcs = D.fcs
  local cmdLaw = mode == "cmd" or fcs ~= "mech"
  local de_c, da_c, dr_c, tvp_c, tvy_c, tvr_c = 0, 0, 0, 0, 0, 0
  local cph, sph, cth = cos(phi), sin(phi), cos(th)
  local nzP = D.nzP * (env.nzK or 1)
  local nzN = D.nzN
  -- 舵面效率按来流：90° 以内照常（大迎角平尾在分离气流里掉一半、副翼掉六成），过了 90°（倒着来流：尾冲、翻过去）效果反过来
  local rev = clamp(cos(aa) * 1.6, -1, 1)
  local Me = qSc * D.Cmde * ctl * (env.pitchK or 1) * (1 - 0.5 * smooth(D.aSr * 0.9, D.aSr * 1.5, aa)) * rev
  local daK = (1 - 0.6 * stallK) * rev
  local La = qSb * D.Clda * ctl * daK
  local Nr = qSb * D.Cndr * ctl * rev
  -- 飞控按舵效求舵偏：舵效太小（快没速度了）或者反过来时别除出无穷大、别打反
  local function safeDiv(need, k, sgn) if k * sgn < 1 then k = sgn end return need / k end
  local tvc = D.tvc
  local tvP = tvc and tvc.p * RAD or 0
  local tvY = tvc and tvc.y * RAD or 0
  if env.ko then inp = { mode = "cmd", n = 0.55, p = 0, r = 0, thr = inp.thr } mode = "cmd" cmdLaw = true end
  if cmdLaw then
    local bw = D.bw * ((mode == "cmd" and fcs == "mech") and 0.75 or 1)
    -- 俯仰：过载指令（松杆时按坡度补偿到保持航迹的过载）→ 迎角指令（不超迎角限制）→ 俯仰角速度指令 → 动态逆求升降舵（和推力矢量）
    local n0 = cth * (cph + smooth(1.05, 0.85, abs(phi)) * (1 / math.max(cph, 0.4) - cph))
    local nc
    if mode == "cmd" then
      nc = inp.n or n0
    else
      local s = shape(clamp(inp.sy or 0, -1, 1))
      nc = (s >= 0) and lerp(n0, nzP, s) or lerp(n0, nzN, -s)
    end
    nc = clamp(nc, nzN, nzP)
    F.nf = F.nf + (nc - F.nf) * (1 - exp(-h / D.tn))
    -- 迎角上限：电传按限制器；增稳的杆拉到最大升力系数为止（米格-29 的限制器能硬拉过去）；教官飞的不进失速
    local aMaxC
    if fcs == "fbw" or mode == "cmd" then aMaxC = D.aLr or D.aSr * 0.92
    else aMaxC = lerp(D.aSr * 0.97, D.aSr + 0.14, smooth(0.9, 1, abs(inp.sy or 0))) end   -- 增稳：杆拉到底能硬拉过最大升力、进失速
    local flCL = fl * D.flapCL
    local clReq = F.nf * m * G0 / (qS * liftK) - flCL
    local ac = clamp(CLinv(D, clReq), -D.aSN * 0.95, aMaxC)
    -- 增稳（F-15、F-14、米格-29）：杆拉到底、要的升力又超过最大升力时，硬拉过失速迎角（进失速，掉翼）
    if fcs == "cas" and mode == "stick" and clReq >= D.CLm * 0.98 then
      ac = lerp(ac, D.aSr + 0.14, smooth(0.9, 1, abs(inp.sy or 0)))
    end
    local nAch = (CLof(D, ac, fl) * liftK) * qS / (m * G0)
    local qk = smooth(4000, 16000, qb)
    -- 跟随的增益按动压排：原来低速只有高速的四成（1.4 → 3.6、3.5 → 7、7 → 13），慢的时候拉杆、压杆反应得慢，快了又冲——
    --   低速抬到高速的七成多（舵面真没劲的时候照样跟不上：舵偏、舵偏速率有限），高速不变
    local ka = lerp(2.6, 3.6, qk) * bw
    local qc = clamp(ka * (ac - al) + G0 / Vn * (nAch - uY), -1.5, 1.5)
    -- 过失速机动（T 解除迎角限制；用户待办「飞控放开机动：大迎角、失速后、推力矢量、尾冲」）：杆直接要俯仰角速度，
    --   飞控不再管迎角、过载——拉满杆机头仰过 90° 再推回来是眼镜蛇，有推力矢量的低速一直拉着能翻一整圈（库尔比特）；
    --   松杆：飞控把迎角拉回到配平（在限制以内），不会一直挂在大迎角上；能拉多快看真的力矩（平尾在分离气流里没劲，推力矢量顶上）
    local ovr = inp.ovr and mode == "stick"
    if ovr then
      local s = shape(clamp(inp.sy or 0, -1, 1))
      local qmx = tvc and 1.6 or 1.0
      if abs(s) > 0.05 then
        qc = s * qmx
      else
        qc = clamp(-2 * (al - ac), -qmx, qmx)
      end
    end
    -- 迎角限制的预见（电传、教官）：迎角变化率 = 俯仰角速度 − 航迹转动角速度。离限制还剩 dA，按平尾推满（加推力矢量）能打出的低头角加速度，
    --   只许以「刹得住」的速度往限制靠；太慢了托不住（航迹往下掉）时机头跟着航迹往下压——原来低速满杆照样一头冲过限制（歼-11 拉到 38°）
    if (fcs == "fbw" or mode == "cmd") and not ovr then
      local Mdn = abs(Me) * D.der * 0.8 + Tl * sin(tvP) - qSc * (D.Cm0 + D.Cma * sin(al))
      local qdd = math.max(Mdn / Iyy, 0.05)
      local gd = G0 / Vn * ((CLof(D, al, fl) * liftK) * qS / (m * G0) - uY)   -- 航迹现在往上转多快（负的：托不住，往下掉）
      local qcap = gd + sqrt(2 * qdd * math.max(aMaxC - al, 0) * 0.6)
      if qc > qcap then qc = math.max(qcap, -1.5) end
    end
    local kq = lerp(5.2, 7, qk) * bw
    local Mreq = Iyy * kq * (qc - q) - (Izz - Ixx) * p * r
    local M0 = qSc * (D.Cm0 + D.Cma * sin(al) + D.Cmq * qh + CmSt + (env.Mext or 0))
    local need = Mreq - M0
    if tvP > 0 and T > 1000 then
      -- 推力矢量：分一部分力矩给喷口（舵面快饱和了全给它）——低速、大迎角平尾没劲时还拉得动
      local deFull = safeDiv(need, Me, (rev >= 0) and -1 or 1)
      local share = 0.35 + 0.65 * smooth(0.5, 1, abs(deFull) / D.der)
      tvp_c = clamp(asin(clamp(need * share / Tl, -1, 1)), -tvP, tvP)
      need = need - Tl * sin(F.tvp)
    end
    de_c = safeDiv(need, Me, (rev >= 0) and -1 or 1)
    -- 滚转：角速度指令（松杆保持坡度，坡度 12° 以内慢慢改平）
    local pc
    if mode == "cmd" then
      pc = inp.p or 0
    else
      local s = shape(clamp(inp.sx or 0, -1, 1))
      -- 飞控按动压、迎角排滚转角速度上限：快到最大允许速度时收三成多（结构载荷），大迎角时收（防惯性耦合）
      local qv = 0.5 * 1.225 * D.vne * D.vne
      local sched = (1 - 0.45 * smooth(0.55 * qv, 1.1 * qv, qb)) * (1 - 0.6 * smooth(0.5 * D.aSr, D.aSr, aa))
      if abs(s) > 0.01 then pc = s * D.pmaxr * sched
      elseif inp.levelHard then pc = clamp(-3 * phi, -0.5 * D.pmaxr, 0.5 * D.pmaxr)   -- 贴着跑道：机翼摆平
      else pc = 0 end   -- 松杆保持坡度（电传的姿态保持；原来小坡度会自己摆平，点一下 D 压的几度又被摆回去）
    end
    -- 前置滤波：压杆按型号的时间常数起来；松杆（往零收、反打）快三倍——滚得起来要时间，停住要干脆（用户 11-25「松手一两帧就收住」）
    local tpe = (abs(pc) < abs(F.pf) or pc * F.pf < 0) and D.tp * 0.35 or D.tp
    F.pf = F.pf + (pc - F.pf) * (1 - exp(-h / tpe))
    local kp = lerp(10, 13, qk) * bw
    local Lreq = Ixx * kp * (F.pf - p) - (Iyy - Izz) * q * r
    -- 飞控不知道哪边翼尖先失速（掉翼是扰动，只靠角速度反馈去顶；失速时副翼也不灵了，顶不住）
    local L0 = qSb * (D.Clb * sbe + Clp * ph + D.Clr * rh + (env.Lext or 0))
    da_c = safeDiv(Lreq - L0, La, (rev >= 0) and 1 or -1)
    -- 双发推力矢量：两个喷口差动偏转也出滚转力矩（苏-35、苏-57 真机这么管滚转）——副翼在失速气流里没劲时顶上
    if tvP > 0 and (D.ne or 2) >= 2 and T > 1000 then
      local ys = 0.06 * D.b   -- 喷口离中线约 0.85 米（翼展 14 米）
      local short = (Lreq - L0) - La * clamp(da_c, -D.dar, D.dar)
      tvr_c = clamp(asin(clamp(short / (T * ys), -1, 1)), -tvP, tvP)
    end
    -- 偏航：协调转弯（偏航角速度跟着坡度）+ 脚蹬要侧滑（用户待办「方向舵侧滑」：踩右舵机头偏右、飞机侧着往前滑；
    --   满舵的侧滑角按动压收：低速约 12°、快了约 4°——垂尾、机身受不了大侧滑），没踩舵就是侧滑归零
    --   过失速 + 推力矢量：脚蹬直接要偏航角速度（低速原地甩头）
    local rc
    if mode == "cmd" then
      rc = G0 / Vn * sph * cth + 3 * be + (inp.r or 0)
    else
      local ped = shape(clamp(inp.sz or 0, -1, 1))
      if ovr and tvY > 0 then
        rc = G0 / Vn * sph * cth + ped * 0.9 + 3 * be * (1 - abs(ped))
      else
        local qvd = 0.5 * 1.225 * D.vne * D.vne
        local bc = -ped * RAD * lerp(12, 4, smooth(0.25 * qvd, 0.8 * qvd, qb))
        rc = G0 / Vn * sph * cth + 3 * (be - bc) + ped * 0.12
      end
    end
    local Nreq = Izz * 4.5 * bw * (rc - r) - (Ixx - Iyy) * p * q
    local N0 = qSb * (Cnb * sbe + D.Cnr * rh + D.Cnp * ph + D.Cnda * F.da)
    local needN = Nreq - N0
    if tvY > 0 and T > 1000 then
      tvy_c = clamp(asin(clamp(needN * 0.4 / Tl, -1, 1)), -tvY, tvY)
      needN = needN - Tl * sin(F.tvy)
    end
    dr_c = safeDiv(needN, Nr, (rev >= 0) and -1 or 1)
  else
    -- 机械操纵：杆直接对舵面。传动比按动压排（满杆的稳态过载约是过载上限的 1.05 倍：高速时不会一把拉爆，慢了满杆照样拉进失速）；
    --   自动配平到 1 g（慢慢跟着速度改）；有阻尼器的加上
    -- 稳态拉 n 个 g 要多大舵偏：迎角照真的升力曲线（拉不出来就是失速迎角再多 7°），加上拉起时的俯仰阻尼
    local pk = ctl * (env.pitchK or 1)
    local function deFor(nn)
      local cl = nn * m * G0 / (qS * liftK) - fl * D.flapCL
      local a = (cl >= D.CLm) and (D.aSr + 0.12) or CLinv(D, cl)
      local qs = G0 * (nn - uY) / Vn
      return clamp(-(D.Cm0 + D.Cma * sin(a) + D.Cmq * qs * D.c / (2 * Vn)) / (D.Cmde * math.max(pk, 0.05)), -D.der, D.der * 0.8)
    end
    local trimT = deFor(uY)
    F.trim = F.trim and (F.trim + (trimT - F.trim) * (1 - exp(-h / 1.2))) or trimT
    local s = shape(clamp(inp.sy or 0, -1, 1))
    local tgt = (s >= 0) and lerp(F.trim, deFor(nzP * 1.05), s) or lerp(F.trim, deFor(nzN), -s)
    -- 俯仰阻尼器（洗出滤波：只挡变化，不改稳态）
    F.qf = (F.qf or q) + (q - (F.qf or q)) * (1 - exp(-h / 1.0))
    de_c = tgt + D.Kq * (q - F.qf)
    -- 副翼：满杆的稳态滚转角速度不超过 pmax；高速时铰链力矩大、舵偏不满（老飞机高速副翼发硬）
    local pPerDa = (D.Clda / math.max(abs(Clp), 0.05)) * (2 * Vn / D.b)
    local daFull = math.min(D.dar * clamp(sqrt(30000 / math.max(qb, 1)), 0.35, 1), D.pmaxr / math.max(pPerDa, 1e-3))
    local sx = shape(clamp(inp.sx or 0, -1, 1))
    if abs(sx) < 0.01 and inp.levelHard then sx = clamp(-phi * 2.5, -0.7, 0.7) end
    da_c = sx * daFull
    dr_c = -shape(clamp(inp.sz or 0, -1, 1)) * D.drr * clamp(sqrt(20000 / math.max(qb, 1)), 0.3, 1) + D.Kr * r
  end
  -- 舵机：限偏度、限速率（平尾往下打的范围小一点）
  F.de = moveTo(F.de, clamp(de_c, -D.der, D.der * 0.8), D.rder * h)
  F.da = moveTo(F.da, clamp(da_c, -D.dar, D.dar), D.rdar * h)
  F.dr = moveTo(F.dr, clamp(dr_c, -D.drr, D.drr), D.rdrr * h)
  if tvc then
    local tr = tvc.r * RAD * h
    F.tvp = moveTo(F.tvp, tvp_c, tr)
    F.tvy = moveTo(F.tvy, tvy_c, tr)
    F.tvr = moveTo(F.tvr or 0, tvr_c, tr)
  end

  ---------------------------------------------------------------- 力
  local CL = CLof(D, al, fl) * liftK
  -- 大迎角（机腹迎风）按平板的阻力；倒着来流（机尾朝前）整架飞机的形阻另加
  local CD = D.CD0 + (env.dCD0 or 0) + D.CDw * waveK(D, M) + D.Kc * kInd * CL * CL + 1.2 * sin(al) ^ 2 * stallK + 0.25 * smooth(1.7, 2.6, aa)
    + 0.03 * (abs(F.de) + abs(F.dr)) + D.gearCD * (inp.gear or 0) + 0.03 * fl + (inp.brake and D.sb or 0)
  local CY = D.CYb * sbe + D.CYdr * F.dr
  local ca, sa = cos(al), sin(al)
  local cT = cos(F.tvp) * cos(F.tvy)
  local Fx = qS * (CL * sa - CD * ca) + T * cT
  local Fy = qS * CY - T * sin(F.tvy)
  local Fz = qS * (-CL * ca - CD * sa) + T * sin(F.tvp)
  ---------------------------------------------------------------- 力矩
  local Lm = qSb * (D.Clb * sbe + Clp * ph + D.Clr * rh + D.Clda * ctl * daK * F.da + D.Cldr * F.dr + (env.Lext or 0) + F.drop * dropK)
    + T * 0.06 * D.b * sin(F.tvr or 0)
  local Mm = qSc * (D.Cm0 + D.Cma * sin(al) + D.Cmq * qh + CmSt + (env.Mext or 0)) + Me * F.de + Tl * sin(F.tvp)
  local Nm = qSb * (Cnb * sbe + D.Cnr * rh + D.Cnp * ph + D.Cnda * F.da) + Nr * F.dr + Tl * sin(F.tvy)
  ---------------------------------------------------------------- 积分（半隐式欧拉）
  -- 机体力（前右下）→ 世界：右 × Fy + 上 × (−Fz) + 前 × Fx（前 = −后）
  local ax = (rX * Fy - uX * Fz - bX * Fx) / m
  local ay = (rY * Fy - uY * Fz - bY * Fx) / m - G0
  local az = (rZ * Fy - uZ * Fz - bZ * Fx) / m
  Vx, Vy, Vz = Vx + ax * h, Vy + ay * h, Vz + az * h
  F.vx, F.vy, F.vz = Vx, Vy, Vz
  -- 收住滚转（用户 11-28「惯性的意思是 飞机滚筒做着 然后突然不做滚筒 惯性要能收住」，照战雷）：
  --   要的滚转角速度（电传 / 教官：前置滤波后的指令；机械操纵：松杆就是 0）比现在的小、或者反过来——另加一个刹车力矩把多出来的那截收掉，
  --   不受副翼偏度、偏转速率限制（只靠副翼：打满反向要零点几秒，满速滚转松手还要多滚 40～76°；战雷里一松手十几二十度就停）。
  --   只在「要停 / 要慢下来」时起作用（加速滚转不管，满杆滚转角速度照旧）；接近失速（掉翼、自转）时不刹，掉翼照样掉
  do
    local pWant
    if cmdLaw then
      pWant = F.pf
    elseif abs(inp.sx or 0) < 0.02 and not inp.levelHard then
      pWant = 0
    end
    if pWant and (abs(pWant) < abs(p) or pWant * p < 0) then
      -- 接近失速迎角（八成起）就逐渐不刹：掉翼、自转照真的来（机械操纵低速拉满杆一边机翼先掉，滚过去机头才掉得下来、改得出）
      Lm = Lm - Ixx * (D.rollBrake or (cmdLaw and ROLL_BRAKE or ROLL_BRAKE_MECH)) * (1 - smooth(0.8 * D.aSr, D.aSr, aa)) * (p - pWant)
    end
  end
  p = p + (Lm + (Iyy - Izz) * q * r) / Ixx * h
  q = q + (Mm + (Izz - Ixx) * p * r) / Iyy * h
  r = r + (Nm + (Ixx - Iyy) * p * q) / Izz * h
  F.p, F.q, F.r = p, q, r
  -- 姿态：机体角速度换到 Roblox 局部轴（X 右 = 俯仰 q、Y 上 = −r、Z 后 = −p），q̇ = ½ q ⊗ (0, Ω)
  local ox, oy, oz = q, -r, -p
  local dw = 0.5 * (-x * ox - y * oy - z * oz)
  local dx = 0.5 * (w * ox + y * oz - z * oy)
  local dy = 0.5 * (w * oy + z * ox - x * oz)
  local dz = 0.5 * (w * oz + x * oy - y * ox)
  w, x, y, z = w + dw * h, x + dx * h, y + dy * h, z + dz * h
  local nq = sqrt(w * w + x * x + y * y + z * z)
  F.qw, F.qx, F.qy, F.qz = w / nq, x / nq, y / nq, z / nq
  F.al, F.be, F.M, F.Va, F.T, F.qb = al, be, M, Va, T, qb
  F.nz = -Fz / (m * G0)
  F.phi, F.th = phi, th
  F.ax, F.ay, F.az = ax, ay + G0, az   -- 不含重力的加速度（镜头用）
  return Vx * h, Vy * h, Vz * h
end

---------------------------------------------------------------- 性能（测试、机库信息卡）

-- 海平面平飞的配平：速度 V（m/s）、质量 m → 迎角、需用推力
function FM.trimLevel(D, m, V, rho)
  rho = rho or 1.225
  local qS = 0.5 * rho * V * V * D.S
  local cl = m * G0 / qS
  local a = CLinv(D, cl)
  local M = V / 340.3
  local CD = D.CD0 + D.CDw * waveK(D, M) + D.Kc * cl * cl
  return a, qS * CD, cl
end

-- 能量机动（某一速度、高度、质量）：瞬时过载（升力 / 迎角限制 / 过载限制拉得出的）、持续过载（推力 = 阻力）、
--   对应的转弯角速度 rad/s、平飞剩余推力的加速度 m/s²；thr 默认全推力
function FM.em(D, m, V, h, thr, dCD0)
  local rho, sos = FM.atmo(h or 0)
  local W = m * G0
  local E = FM.sweep(D, V / sos)
  local qS = 0.5 * rho * V * V * E.S
  local M = V / sos
  local ab = ((thr or 130) > 100 and E.Ta > E.Tm) and ((thr or 130) - 100) / 30 or 0
  local T = thrustOf(E, math.min(thr or 130, 100) / 100, ab, M, rho, V)
  local CD0 = E.CD0 + (dCD0 or 0) + E.CDw * waveK(E, M)
  local aMax = E.aLr or E.aSr
  local clMax = CLof(E, aMax, 0)
  local ni = math.min(E.nzP, qS * clMax / W)
  local D0 = qS * CD0
  local ns = math.min(ni, sqrt(math.max(0, (T - D0) * qS / (E.Kc * W * W))))
  local function w(n) return (n > 1) and G0 * sqrt(n * n - 1) / V or 0 end
  return { ni = ni, ns = ns, wi = w(ni), ws = w(ns), acc = (T - D0 - E.Kc * W * W / qS) / m, T = T, D0 = D0 }
end

-- 平飞最大速度（m/s，海平面附近 1000 米、这个质量、thr 油门）：剩余推力加速度过零的速度（二分）
--   dCD0：外挂的零升阻力增量（FM.loadout 的 dCD0；不给就是干净构型，同原来）
function FM.vTop(D, m, thr, h, dCD0)
  -- 从失速速度往上找最后一个还有剩余推力的速度（再二分细找）：太慢时诱导阻力大、加速度也是负的，不能从低速一头二分
  local rho = FM.atmo(h or 1000)
  local vs = sqrt(2 * m * G0 / (rho * D.S * D.CLm))
  local lo, hi = nil, nil
  for V = vs * 1.15, 720, 5 do
    if FM.em(D, m, V, h or 1000, thr, dCD0).acc > 0 then lo = V elseif lo then hi = V break end
  end
  if not lo then return vs * 1.15 end
  hi = hi or 720
  for _ = 1, 30 do
    local mid = (lo + hi) / 2
    if FM.em(D, m, mid, h or 1000, thr, dCD0).acc > 0 then lo = mid else hi = mid end
  end
  return lo
end

-- 一型的性能摘要（机库信息卡、测试）：海平面附近（1000 米）、一半内油 + 两枚中距弹；
--   给了 m、dCD0（FM.loadout 算的这一套挂载）就按那套算。roc 最大爬升率 m/s（全加力、剩余功率 = 剩余推力 × 速度 / 重量）、rocV 在哪个速度
function FM.card(D, m, dCD0)
  m = m or (D.m0 + 0.5 * D.fi + 320)
  local W = m * G0
  local rho = FM.atmo(1000)
  local best = { ws = 0, wi = 0, roc = 0 }
  for V = 60, 420, 5 do
    if V < D.vne * 1.02 then
      local e = FM.em(D, m, V, 1000, nil, dCD0)
      if e.ws > best.ws then best.ws, best.vs = e.ws, V end
      if e.wi > best.wi then best.wi, best.vi = e.wi, V end
      local roc = e.acc * V / G0
      if roc > best.roc then best.roc, best.vr = roc, V end
    end
  end
  return { m = m, tw = D.Ta / W, wl = m / D.S, vs = sqrt(2 * W / (rho * D.S * D.CLm)), str = best.ws, strV = best.vs, itr = best.wi, itrV = best.vi,
    roll = D.pmax, nz = D.nzP, roc = best.roc, rocV = best.vr }
end

-- 性能卡（整备「挂载」页右栏：空挂 vs 当前）：这一质量、这一阻力增量下的极速（军推 / 加力，1000 米）、推重比、持续 / 瞬时转弯、最大爬升率——
--   全是上面现成的 vTop / card（em）算的；m、dCD0 一般来自 FM.loadout
function FM.perf(D, m, dCD0)
  local c = FM.card(D, m, dCD0)
  c.vMil = FM.vTop(D, m, 100, 1000, dCD0)
  c.vAB = (D.Ta > D.Tm) and FM.vTop(D, m, 130, 1000, dCD0) or c.vMil
  c.dCD0 = dCD0 or 0
  return c
end

return FM
