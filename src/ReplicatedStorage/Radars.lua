-- 全面大战场（共用）——机载对空雷达：每型、每个科技树版本自己的雷达（纯 Lua、不碰 Roblox API：客户端 Radar.lua / Fly.lua / WtFlight.lua / TechUI.lua、
--   AirDefs（补到 d.radar）、lune 测试 tools/test/radar.luau 都能 require / luau.load）
--   用户 11-24 夜：「战雷我记得不同带有雷达的载具会根据雷达型号有雷达扫描图的，为雷达锁定式导弹提供引导，所以也有 39 机动的这种说法」
--   用户 11-27：「飞机雷达按型号照战雷做、能用键控制雷达方向」
--   数照真机（公开资料取中间值，出处在文件末尾）；拿不准的数在注释里标「估」，整部雷达多是外界说法的写 est = true（资料卡上也写「估」）
--   km：对战斗机（3～5 m²）迎头的发现距离；游戏量程 range = K·√km（作战区只有十几公里，按根号压缩；APG-68 80 km → 28801 格 ≈ 10.3 km，
--     跟原来 AirDefs RADAR 表 ×2.5 的比例差 5% 以内）；lock = range × lockK（单目标跟踪 STT 能锁的距离）
--   字段：name 中文全名、en 英文全名、short 屏上写的短名（shortEn：英文界面另写）；kind pd 脉冲多普勒 / pulse 脉冲（pulse = true：另有脉冲模式，不怕置零、怕地杂波）；
--     arr mech 机械扫描 / pesa 无源相控阵 / aesa 有源相控阵；ldK 下视时量程乘几；az 方位万向架 ±°；elU / elD 俯仰万向架（往上 / 往下）；
--     rate 扫描速度 °/s（机械扫描约 60、相控阵快）；scans 搜索方式 { 方位半宽°, 行数[, far = 量程乘几] }（第一个是默认）；
--     tws 边扫边跟批数（0 = 没有）、eng 同时攻击几个、twsScans 边扫边跟只能用的扫描方式（序号）；
--     acm 近战模式（RD.ACM 的键）、acmGeo 改写这部雷达的近战扫描区、acmTag 改写屏上的缩写；notch 置零门限（目标对地速度在视线上的分量低于它就看不见，格 / 秒）；
--     rwr 敌方告警器上的代号；lpi 敌方告警器发现距离乘几（低截获）
--   算好的（老代码照旧读 name / kind / range / lock / az / el / notch）：key、range、lock、el = max(elU, elD)、ldK（没写是 1）
--   RD.of(id, treeKey)：这一型（科技树的版本优先，同 FlightModel.VAR）的雷达，没有对空雷达返回 nil。**不退回 like**：苏-27 借苏-35S 的模型，雷达照旧是 N001
--   RD.frame(r, i)：第 i 种扫描方式扫一帧几秒（行数 × 2 × 半宽 / 扫描速度）；RD.half(r)：默认扫描方式的方位半宽（告警器，第 6 步换成对方的真实扫描区）
--   RD.modes(r)：这部雷达有的模式（rws 总有；tws 要 r.tws > 0；acm 要有近战模式）；RD.scanOk(r, mode, i)：这种模式能不能用第 i 种扫描方式
--     （AWG-9 的边扫边跟只能用 twsScans 那两种）；RD.acmGeo(r, k)：近战模式 k 的扫描区（这部雷达的 acmGeo 优先）；RD.fade(r, i)：亮点多久暗掉
--   RD.card(r, T, en)：资料卡「雷达」那一节的行
--   **以后加有雷达的飞机**：RD.OF 加一行（AirDefs 型号 → 雷达键）；科技树里借型号（base）的版本雷达不一样的，RD.VAR 加一行（科技树键 → 雷达键）；
--     给借型号的版本建了自己的 AirDefs 型号以后，RD.OF 补上新型号、RD.VAR 删掉那一行
local RD = {}
RD.K = 3220        -- 游戏量程 = K·√真实公里（格）
RD.M = 2.8         -- 1 米多少格（AirDefs 载入时改成 AirDefs.M）
RD.BAR = 3.5       -- 一行的俯仰间隔°
RD.BEAM = 2        -- 波束半宽°
RD.ACM_KM = 18.5   -- 近战自动截获（真机 10 海里 → RD.K·√18.5 ≈ 13850 格）
RD.ACQ = math.floor(RD.K * math.sqrt(RD.ACM_KM) + 0.5)   -- 近战模式里这个距离以内第一个扫到的自动进单目标跟踪（格）
RD.MEM = 2         -- 单目标跟踪丢了目标：先按记忆外推几秒（屏上 STT MEM），还是没有再丢锁、回到原来的扫描
RD.SLEW = { az = 40, el = 25, wheel = 2 }   -- 挪扫描中心：←→ 方位 °/秒（11-28 起不用按 Alt）、Alt+↑↓ 俯仰 °/秒、Alt+滚轮 一格几度（像真机油门杆上的天线俯仰轮）
-- 近战扫描区（机体坐标）：平显 30°×20°、竖扫 10°×60°、瞄准线、可挪 60°×10°、头盔
RD.ACM = { hud = { az = 15, el0 = -10, el1 = 10 }, vert = { az = 5, el0 = -10, el1 = 50 }, bore = { az = 1.5, el0 = -1.5, el1 = 1.5 },
  slew = { az = 30, el0 = -5, el1 = 5, slew = true }, hmd = { az = 2, el0 = -2, el1 = 2, head = true } }
-- 屏上写的真机缩写（用户 11-27 定的：中英一样）；某部雷达叫法不一样的写在它的 acmTag 里（F-14 的 PLM / VSL）
RD.ACM_TAG = { hud = "HUD", vert = "VS", vertLo = "VS LO", bore = "BORE", slew = "SLEW", hmd = "HMD", pal = "PAL" }
RD.MODE_TAG = { rws = "RWS", tws = "TWS", stt = "STT", acm = "ACM", mem = "MEM" }

local function inh(b, o)
  local t = {}
  for k, v in pairs(b) do t[k] = v end
  for k, v in pairs(o) do t[k] = v end
  return t
end
local S4 = { { 60, 2 }, { 60, 4 }, { 30, 4 }, { 10, 4 } }
local T = {}

---------------------------------------------------------------- 中国（型号、距离多是外界说法：est）

-- 歼-8II：208A 型单脉冲，约 40 km，不能下视，没有真正的超视距
T.sl8a = { name = "SL-8A（208A 型）单脉冲", en = "SL-8A (Type 208A) monopulse", short = "SL-8A", kind = "pulse", arr = "mech", km = 40, lockK = 0.75,
  az = 45, elU = 30, elD = 30, rate = 60, scans = { { 45, 2 }, { 20, 2 } }, tws = 0, acm = { "bore" }, notch = 0, rwr = "J8" }
-- 歼-10A：距离 100～150 km、批数各家说法不一（估）
T.klj3 = { name = "KLJ-3（1473 型）脉冲多普勒", en = "KLJ-3 (Type 1473) pulse-Doppler", short = "KLJ-3", kind = "pd", arr = "mech", km = 100, ldK = 0.8,
  az = 60, elU = 60, elD = 60, rate = 60, scans = S4, tws = 10, eng = 2, acm = { "hud", "vert", "bore" }, notch = 60, rwr = "J10", est = true }
-- 歼-10C：也有说早期装 KLJ-7A（估）
T.klj10 = { name = "KLJ-10A 有源相控阵（型号说法不一）", en = "KLJ-10A AESA (designation disputed)", short = "KLJ-10A", kind = "pd", arr = "aesa", km = 130, lockK = 0.85, ldK = 0.9,
  az = 60, elU = 60, elD = 60, rate = 150, scans = S4, tws = 15, eng = 4, acm = { "hud", "vert", "bore", "hmd" }, notch = 45, rwr = "J10", est = true }
-- 歼-11B：约 150 km 是论坛说法，取 120（估）
T.t1493 = { name = "1493 型脉冲多普勒（也有写 1474 型）", en = "Type 1493 pulse-Doppler (also reported as Type 1474)", short = "1493", kind = "pd", arr = "mech", km = 120, ldK = 0.8,
  az = 60, elU = 60, elD = 55, rate = 60, scans = S4, tws = 10, eng = 4, acm = { "vert", "bore", "hmd" }, notch = 60, rwr = "J11", est = true }
-- 型号没公开的有源相控阵（数都是估的）
local AESA = { short = "有源相控阵", shortEn = "AESA", kind = "pd", arr = "aesa", lockK = 0.85, ldK = 0.9, az = 60, elU = 60, elD = 60, rate = 150, scans = S4,
  tws = 20, eng = 6, acm = { "hud", "vert", "bore", "hmd" }, notch = 45, est = true }
T.j16 = inh(AESA, { name = "有源相控阵（歼-16，型号未公开）", en = "AESA (J-16, designation not public)", km = 170, rwr = "J16" })
T.j15t = inh(AESA, { name = "有源相控阵（歼-15T，型号未公开）", en = "AESA (J-15T, designation not public)", km = 160, rwr = "J15" })
-- 歼-20：1475 是不是装在它上面有争议；外界说 200～300 km（估）
T.klj5 = inh(AESA, { name = "KLJ-5（1475 型）有源相控阵", en = "KLJ-5 (Type 1475) AESA", short = "KLJ-5", shortEn = "KLJ-5", km = 200, notch = 40, lpi = 0.7, rwr = "J20" })
T.j35 = inh(AESA, { name = "有源相控阵（歼-35，型号未公开）", en = "AESA (J-35, designation not public)", km = 160, notch = 40, lpi = 0.7, rwr = "J35" })
T.j36 = inh(AESA, { name = "有源相控阵（歼-36，型号未公开）", en = "AESA (J-36, designation not public)", km = 220, notch = 40, lpi = 0.6, rwr = "J36" })   -- 科技树里没有

---------------------------------------------------------------- 美国、日本

-- F-16A：下视对战斗机约 55.6 km；近战 20°×20°、10°×40°；没有 TWS
T.apg66 = { name = "AN/APG-66 脉冲多普勒", en = "AN/APG-66 pulse-Doppler", short = "APG-66", kind = "pd", arr = "mech", km = 60, ldK = 0.85,
  az = 60, elU = 60, elD = 60, rate = 60, scans = { { 60, 1 }, { 60, 2 }, { 30, 4 }, { 10, 4 } }, tws = 0, acm = { "hud", "vert", "bore" },
  acmGeo = { hud = { az = 10, el0 = -10, el1 = 10 }, vert = { az = 5, el0 = -10, el1 = 30 } }, notch = 65, rwr = "F16" }
-- F-16C Block 50/52：RWS / TWS / VS / SAM / ACM / STT
T.apg68 = { name = "AN/APG-68(V)5 脉冲多普勒", en = "AN/APG-68(V)5 pulse-Doppler", short = "APG-68(V)5", kind = "pd", arr = "mech", km = 80, ldK = 0.85,
  az = 60, elU = 60, elD = 60, rate = 60, scans = S4, tws = 10, eng = 6, acm = { "hud", "vert", "bore", "slew" }, notch = 60, rwr = "F16" }
-- F-2A：对 5 m² 60 海里（110 km）
T.japg1 = { name = "J/APG-1 有源相控阵", en = "J/APG-1 AESA", short = "J/APG-1", kind = "pd", arr = "aesa", km = 110, lockK = 0.85, ldK = 0.9,
  az = 60, elU = 60, elD = 60, rate = 150, scans = S4, tws = 10, eng = 4, acm = { "hud", "vert", "bore" }, notch = 50, rwr = "F2" }
-- F-15A：RWS / VS / STT，没有 TWS
T.apg63 = { name = "AN/APG-63 脉冲多普勒（早期）", en = "AN/APG-63 pulse-Doppler (early)", short = "APG-63", kind = "pd", arr = "mech", km = 100, ldK = 0.8,
  az = 60, elU = 60, elD = 60, rate = 70, scans = { { 60, 2 }, { 60, 4 }, { 30, 6 }, { 10, 8 } }, tws = 0, acm = { "hud", "vert", "bore" }, notch = 60, rwr = "F15" }
-- F-15C（挂 AIM-120 的年代）、F-15J（1981 年的 F-15J 严格说那时还没有 TWS 软件，先按 F-15C 给）
T.apg63c = inh(T.apg63, { name = "AN/APG-63（可编程信号处理机）", en = "AN/APG-63 (programmable signal processor)", km = 110, tws = 10, eng = 6 })
-- F-15E（1988；2014 年后换的 APG-82 不做）
T.apg70 = inh(T.apg63, { name = "AN/APG-70 脉冲多普勒", en = "AN/APG-70 pulse-Doppler", short = "APG-70", km = 130, tws = 10, eng = 6 })
-- F-15J（M）
T.apg63v1 = inh(T.apg63, { name = "AN/APG-63(V)1（三菱电机许可生产）", en = "AN/APG-63(V)1 (Mitsubishi Electric licence)", short = "APG-63(V)1", km = 120, tws = 14, eng = 6 })
-- F-14A：RWS 对迎头战斗机约 170 km；TWS 只能用 ±40°×2 或 ±20°×4（一帧约 2 秒），跟踪 24（显示 18）、攻击 6；PLM 是 2.3° 波束，
--   VSL 高 +15～+55°、低 −15～+25°，PAL 40° 一行；另有脉冲搜索 / 脉冲跟踪
T.awg9 = { name = "AN/AWG-9 脉冲多普勒 / 脉冲", en = "AN/AWG-9 pulse-Doppler / pulse", short = "AWG-9", kind = "pd", pulse = true, arr = "mech", km = 170, lockK = 0.75, ldK = 0.85,
  az = 65, elU = 60, elD = 60, rate = 80, scans = { { 40, 2 }, { 65, 2 }, { 65, 4 }, { 20, 4 }, { 10, 8 } }, twsScans = { 1, 4 }, tws = 24, eng = 6,
  acm = { "bore", "vert", "vertLo", "pal" },
  acmGeo = { bore = { az = 1.2, el0 = -1.2, el1 = 1.2 }, vert = { az = 2, el0 = 15, el1 = 55 }, vertLo = { az = 2, el0 = -15, el1 = 25 }, pal = { az = 20, el0 = -2, el1 = 2 } },
  acmTag = { bore = "PLM", vert = "VSL HI", vertLo = "VSL LO" }, notch = 60, rwr = "F14" }
-- F-22A：没有头盔瞄准具
T.apg77 = { name = "AN/APG-77 有源相控阵", en = "AN/APG-77 AESA", short = "APG-77", kind = "pd", arr = "aesa", km = 200, lockK = 0.85, ldK = 0.95,
  az = 60, elU = 60, elD = 60, rate = 200, scans = S4, tws = 20, eng = 6, acm = { "hud", "bore" }, notch = 35, lpi = 0.5, rwr = "F22" }
-- F-35A：头盔显示
T.apg81 = inh(T.apg77, { name = "AN/APG-81 有源相控阵", en = "AN/APG-81 AESA", short = "APG-81", km = 160, acm = { "hud", "bore", "hmd" }, rwr = "F35" })

---------------------------------------------------------------- 俄罗斯（跟踪 / 攻击批数是厂家说法）

-- 米格-29（9.12）：3 m² 迎头 50～70 km、跟踪 40～60 km（目标低于 3000 米时发现 40～70 km）；方位 ±65°、俯仰 +56 / −36°（出口手册）；
--   只能单目标跟踪 + R-27R；头盔瞄准具「窄缝」配光电
T.n019 = { name = "N019 脉冲多普勒（RP-29）", en = "N019 pulse-Doppler (RP-29)", short = "N019", kind = "pd", arr = "mech", km = 70, lockK = 0.8, ldK = 0.75,
  az = 65, elU = 56, elD = 36, rate = 60, scans = { { 65, 2 }, { 30, 4 }, { 20, 6 } }, tws = 0, acm = { "vert", "bore", "hmd" }, notch = 70, rwr = "29" }
-- 苏-27S：3 m² 迎头 80～100 km、尾追 40 km、跟踪约 65 km；方位 ±60°、俯仰 +60 / −55°；只能单目标跟踪 + R-27R / ER
T.n001 = { name = "N001「剑」脉冲多普勒", en = "N001 Myech pulse-Doppler", short = "N001", kind = "pd", arr = "mech", km = 90, lockK = 0.72, ldK = 0.75,
  az = 60, elU = 60, elD = 55, rate = 60, scans = { { 60, 2 }, { 30, 4 }, { 10, 4 } }, tws = 0, acm = { "vert", "bore", "hmd" }, notch = 70, rwr = "27" }
-- 歼-11（早期，苏-27SK 那一套）
T.n001e = inh(T.n001, { name = "N001E「剑」脉冲多普勒（出口型）", en = "N001E Myech pulse-Doppler (export)", short = "N001E", rwr = "J11" })
-- 苏-27SM
T.n001ve = inh(T.n001, { name = "N001VE「剑」（换了新处理机，能打 R-77）", en = "N001VE Myech (new processor, R-77 capable)", short = "N001VE", km = 100, lockK = 0.75, tws = 10, eng = 2 })
-- 苏-30SM：TWS 15 批 / 攻击 4（400 km 是对大目标的）
T.n011m = { name = "N011M「雪豹」无源相控阵", en = "N011M Bars PESA", short = "N011M", kind = "pd", arr = "pesa", km = 140, ldK = 0.85,
  az = 70, elU = 56, elD = 40, rate = 120, scans = { { 70, 2 }, { 60, 4 }, { 30, 4 }, { 10, 6 } }, tws = 15, eng = 4, acm = { "vert", "bore", "hmd" }, notch = 55, rwr = "30" }
-- 苏-35S：平时约 200 km，窄扇区（约 100 平方度）350～400 km（far）；电扫 ±60° 加液压转台，扫描中心能挪到 ±60°（合计 ±120°）；跟踪 30 / 攻击 8（厂家说法）
T.n035 = { name = "N035「雪豹-E」无源相控阵", en = "N035 Irbis-E PESA", short = "N035", kind = "pd", arr = "pesa", km = 200, ldK = 0.85,
  az = 120, elU = 60, elD = 60, rate = 120, scans = { { 60, 2 }, { 60, 4 }, { 30, 4 }, { 5, 3, far = 1.32 } }, tws = 30, eng = 8, acm = { "vert", "bore", "hmd" }, notch = 55, rwr = "35" }
-- T-50（从 T-50-3 起装雷达）：原型机的软件、功率还没到量产型（估）
T.n036t = { name = "N036 有源相控阵（试验型）", en = "N036 AESA (prototype)", short = "N036", kind = "pd", arr = "aesa", km = 160, lockK = 0.85, ldK = 0.9,
  az = 75, elU = 60, elD = 60, rate = 150, scans = S4, tws = 30, eng = 8, acm = { "bore", "hmd" }, notch = 42, rwr = "57", est = true }
-- 苏-57：Sh121 一套（机头 N036-1-01 + 两侧 N036B + 前缘 L 波段阵）；跟踪 60 / 攻击 16（厂家说法）；侧视阵的角度没公开，方位极限保留 75°（估）
T.n036 = inh(T.n036t, { name = "N036「松鼠」有源相控阵（机头 + 两侧侧视阵）", en = "N036 Byelka AESA (nose + side arrays)", km = 190, tws = 60, eng = 16,
  acm = { "hud", "bore", "hmd" }, notch = 40, lpi = 0.7 })

RD.T = T
-- AirDefs 型号 → 默认雷达。没写的没有对空雷达：j6、h6k、gj11、gj2、a10c、mq9、b2、su25、全部直升机
RD.OF = { j8 = "sl8a", j10 = "klj10", j11 = "t1493", j16 = "j16", j15t = "j15t", j20 = "klj5", j35 = "j35", j36 = "j36",
  f16 = "apg68", f15 = "apg63c", f14 = "awg9", f22 = "apg77", f35 = "apg81",
  mig29 = "n019", su27 = "n001", su35 = "n035", t50 = "n036t", su57 = "n036" }
-- 科技树里借型号（base）的版本自己的雷达（同 FlightModel.VAR）
RD.VAR = { cn_j10a = "klj3", cn_j11 = "n001e", us_f16a = "apg66", jp_f2a = "japg1", us_f15a = "apg63", us_f15e = "apg70", jp_f15jm = "apg63v1",
  ru_su27sm = "n001ve", ru_su30sm = "n011m" }

---------------------------------------------------------------- RCS（雷达反射截面）
-- 用户 11-28「引入一下rcs这个概念」：每型迎头、干净构型的 RCS（m²）。公开资料多是估的说法（隐身机各家差一两个数量级），取常见的中间值。
--   雷达方程：同一部雷达能发现的距离 ∝ RCS 的四次方根。km（真实公里）是对 RD.SIGMA0（5 m²，三代战斗机迎头）说的；
--   游戏量程 = K·√km（按根号压缩），所以游戏里按 (σ / σ0)^(1/8) 缩放（RD.rangeK）：F-22（0.0003 m²）只剩三成，轰-6K（60 m²）远三成
--   外挂（弹舱里的不算）每件加一点（RD.STORE_RCS）：隐身机挂了外挂就不再隐身。
--   方位（RD.aspectK）：侧面比迎头大得多（机身侧面、垂尾），尾后也大一点（喷口）：σ(θ) = σ迎头 ·（1 + 7 sin²θ + 1.5·max(0, −cos θ)）
RD.SIGMA0 = 5
RD.RCS = {
  -- 中国（多是估的）
  j6 = 4, j8 = 8, j10 = 1.5, j11 = 12, j15t = 10, j16 = 8, j20 = 0.01, j35 = 0.02, j36 = 0.002, h6k = 60, gj11 = 0.01, gj2 = 1,
  -- 美国、日本
  f16 = 1.2, f15 = 15, f14 = 25, f22 = 0.0003, f35 = 0.005, a10c = 20, b2 = 0.001, mq9 = 1,
  -- 俄罗斯
  mig29 = 5, su27 = 15, su35 = 3, su57 = 0.3, su25 = 10,
  -- 直升机（旋翼的回波大）
  z20 = 8, uh60 = 10, ch47 = 30, mi24 = 15, mi28 = 10, ka52 = 8, tiger = 3, ah1w = 3, ah1s = 3, oh1 = 1, ah64dj = 4, mi8 = 15, nh90 = 6,
  uh1n = 5, z8 = 20, ch47j = 30, uh60ja = 10,
}
RD.RCS_DEF = { jet = 5, heli = 8 }   -- 表里没有的按种类
-- 科技树里借型号的版本 RCS 不一样的（同 RD.VAR：老型号没上吸波涂料、进气道不一样）
RD.RCS_VAR = { cn_j10a = 3, cn_j11 = 15, us_f16a = 1.5, ru_su27sm = 15, ru_su30sm = 12 }
RD.STORE_RCS = { aam = 0.1, sam = 0.1, agm = 0.2, bomb = 0.2, rkt = 0.3, tank = 0.5 }
-- 一架飞机迎头的 RCS：型号（科技树版本优先）+ 外挂。d：AirDefs 的型号；load：每个挂点挂的武器（同 Load 属性拆开的表）；W：AirDefs.W
function RD.rcsOf(d, treeKey, load, W)
  if not d then return RD.SIGMA0 end
  local s = (treeKey and RD.RCS_VAR[treeKey]) or RD.RCS[d.id or ""] or RD.RCS_DEF[d.kind or "jet"] or RD.SIGMA0
  if type(load) == "table" and W then
    for i, wid in ipairs(load) do
      local stn = d.st and d.st[i]
      local w = wid and W[wid]
      if w and stn and not stn.bay then   -- 多联挂架按枚数（火箭巢是一个巢）
        local cnt = (w.kind == "rkt") and 1 or ((stn.n and stn.n[wid]) or 1)
        s = s + (RD.STORE_RCS[w.kind] or 0.1) * cnt
      end
    end
  end
  return s
end
-- cosT：目标机头方向和「目标 → 雷达」的夹角余弦（1 = 迎头、0 = 正侧面、−1 = 尾后）
function RD.aspectK(cosT)
  local c = math.clamp(cosT or 1, -1, 1)
  return 1 + 7 * (1 - c * c) + 1.5 * math.max(0, -c)
end
function RD.rangeK(sigma) return (math.max(sigma or RD.SIGMA0, 1e-6) / RD.SIGMA0) ^ 0.125 end

for k, r in pairs(T) do
  r.key = k
  r.range = math.floor(RD.K * math.sqrt(r.km))
  r.lock = math.floor(r.range * (r.lockK or 0.8))
  r.el = math.max(r.elU, r.elD)
  r.ldK = r.ldK or 1
  if r.iff == nil then r.iff = r.kind == "pd" end   -- 敌我识别（用户 11-28「iff」）：脉冲多普勒这一代都带询问机；老脉冲雷达分不出敌我
end

function RD.of(id, treeKey)
  local k = (treeKey and RD.VAR[treeKey]) or RD.OF[id or ""]
  return k and T[k] or nil
end
function RD.frame(r, i)
  local s = r.scans[i or 1]
  return s[2] * 2 * s[1] / r.rate
end
-- 默认扫描方式的方位半宽（敌方告警器现在按它算「扫没扫到我」——不然苏-35S 的 ±120° 万向架一下子全扫得到；第 6 步同步了对方的扫描区以后换掉）
function RD.half(r) return math.min(r.scans[1][1], r.az) end
function RD.tag(r, k) return (r.acmTag and r.acmTag[k]) or RD.ACM_TAG[k] or string.upper(k) end
function RD.modes(r)
  local m = { "rws" }
  if (r.tws or 0) > 0 then table.insert(m, "tws") end
  if r.acm and #r.acm > 0 then table.insert(m, "acm") end
  return m
end
function RD.scanOk(r, mode, i)
  if not r.scans[i] then return false end
  if mode ~= "tws" or not r.twsScans then return true end
  for _, j in ipairs(r.twsScans) do if j == i then return true end end
  return false
end
function RD.acmGeo(r, k) return (r.acmGeo and r.acmGeo[k]) or RD.ACM[k] end
function RD.fade(r, i) return math.max(2.6, RD.frame(r, i) + 0.8) end

-- 资料卡（TechUI）「雷达」那一节：{ { 字, 是不是标题 }, … }。T(键, …) 是 Lang 的翻译（客户端 G.T），en 英文界面；r 为 nil 写「没有对空雷达」
function RD.card(r, T2, en, sigma)
  T2 = T2 or function(k) return k end
  local rows = { { T2("tech.radar"), true } }
  if sigma then   -- 这一型自己的 RCS（迎头、干净构型）：被别人的雷达多远发现（按 5 m² 的几成）
    table.insert(rows, { T2("tech.rcs", (sigma < 0.1) and string.format("%.3g", sigma) or string.format("%.1f", sigma), string.format("%d", math.floor(RD.rangeK(sigma) * 100 + 0.5))) })
  end
  if not r then
    table.insert(rows, { T2("tech.radar.none") })
    return rows
  end
  local function km(g) return string.format("%.1f", g / RD.M / 1000) end
  table.insert(rows, { (en and r.en) or r.name })
  table.insert(rows, { T2("tech.radar.type", T2("rd.arr." .. r.arr), T2(r.pulse and "rd.kind.pdp" or ("rd.kind." .. r.kind))) })
  table.insert(rows, { T2("tech.radar.det", tostring(r.km), km(r.range), km(r.lock)) .. (r.est and T2("tech.radar.est") or "") })
  table.insert(rows, { T2("tech.radar.fov", tostring(r.az), tostring(r.elU), tostring(r.elD)) })
  local sc = {}
  for _, s in ipairs(r.scans) do
    table.insert(sc, T2("tech.radar.bars", tostring(s[1]), tostring(s[2])) .. (s.far and T2("tech.radar.far", string.format("%.2f", s.far)) or ""))
  end
  table.insert(rows, { T2("tech.radar.scan", table.concat(sc, " · "), tostring(r.rate), string.format("%.1f", RD.frame(r, 1))) })
  table.insert(rows, { T2(r.iff and "tech.radar.iff" or "tech.radar.noIff") })
  if (r.tws or 0) > 0 then
    table.insert(rows, { T2("tech.radar.tws", tostring(r.tws), tostring(r.eng or 1)) })
  else
    table.insert(rows, { T2("tech.radar.stt") })
  end
  if r.acm and #r.acm > 0 then
    local a = {}
    for _, k in ipairs(r.acm) do table.insert(a, T2("rd.acm." .. k) .. (en and (" (" .. RD.tag(r, k) .. ")") or ("（" .. RD.tag(r, k) .. "）"))) end
    table.insert(rows, { T2("tech.radar.acm", table.concat(a, en and ", " or "、")) })
  end
  return rows
end

return RD

-- 来源（11-27 调研只用了搜索摘要：en.wikipedia.org、f14.manuals.heatblur.se 在调研会话的网络里打不开，要细核得在会话网络设置里放行这两个域名）
--   APG-66：en.wikipedia.org/wiki/AN/APG-66 ；globalsecurity.org/military/systems/aircraft/systems/an-apg-66.htm
--   APG-68 模式：scribd.com/doc/255407392/APG-68-Guide-Radar
--   APG-63 / APG-70 / APG-63(V)1、F-15J：en.wikipedia.org/wiki/AN/APG-63_radar_family ；flightglobal.com/melco-starts-f-15j-radar-upgrade/66178.article
--   AWG-9：f14.manuals.heatblur.se/systems/radar/general_operation.html ；f14.manuals.heatblur.se/systems/radar/acm_modes.html
--   J/APG-1：en.wikipedia.org/wiki/J/APG-1 ；N001：en.wikipedia.org/wiki/Mech_radar
--   N019：microwavejournal.com/articles/1805-got-you-covered ；secretprojects.co.uk/goto/post?id=738507
--   N011M、N035：en.wikipedia.org/wiki/Bars_radar ；en.wikipedia.org/wiki/Irbis-E ；N036：deagel.com/Sensor%20Systems/Byelka/a002797
--   APG-77：northropgrumman.com/what-we-do/mission-solutions/radars/an-apg-77-aesa ；208A（歼-8II）：wikipedia.org/wiki/J-8II
--   中国雷达（KLJ-3、1493、KLJ-10A、KLJ-5）：secretprojects.co.uk/threads/chinese-airborne-radars.19725/post-605387 ；
--     airuniversity.af.edu/CASI/Display/Article/4250249/a-look-at-the-j-20-aesa-radar/ ；globalsecurity.org/military/world/china/j-11bg.htm
--   战雷默认键（Alt+R 开关、Alt+T 选目标、Alt+F 锁定）：wiki.warthunder.com「Airborne radars」（11-27 搜索摘要）
