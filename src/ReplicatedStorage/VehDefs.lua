-- Roblox全面大战场——地面载具的型号数据（服务器、客户端共用）：尺寸、速度、炮塔、武器、车轮 / 负重轮、烟幕弹发射筒、瞄准镜
--   单位：格（1 米约 2.8 格，和 Roblox 的人一样比例）。车的坐标系：原点在车底中心（着地），X 右、Y 上、−Z 朝前
--   服务器的命中盒是 W × H × L 的方块，中心在原点上 H/2；客户端按 arch（tracked 履带 / wheeled 轮式）和各项参数拼零件模型
--   炮塔：pivot 是转轴（相对车底），trav 每秒转几度，elev 俯仰范围（度）；炮：gun.pivot 是耳轴（相对炮塔转轴），len 长、cal 粗
--   烟幕弹：smoke.banks 每组一个发射架（相对炮塔转轴的位置、朝向角 yaw 度——0 朝前、正数往右），n 管，各管在架上扇形张开、仰 35°
local VehDefs = {}
local V = Vector3.new

-- 武器（载具用）：kind shell 有弹道的炮弹（打到就炸）、gun 机枪（直射判定）、arty 曲射（准星下的地面）、
--   rate 两发间隔（秒）、mag 一个弹匣 / 弹舱、reload 换弹、reserve 备弹（不算弹匣里的）；speed 弹速（格 / 秒）、drop 下坠（重力倍数）
--   坦克炮（gun125 / gun120 / gun105）真正打出去按 Ballistics.lua 的弹种（初速、阻力、真实重力）；这里的 speed、drop 是默认弹种的值（别处估飞行时间用）
VehDefs.W = {
  gun125 = { kind = "shell", dmg = 640, speed = 4872, drop = 0.14, splash = 6, rate = 6.5, mag = 1, reload = 0, reserve = 30, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },
  gun125r = { kind = "shell", dmg = 640, speed = 4648, drop = 0.14, splash = 6, rate = 6.5, mag = 1, reload = 0, reserve = 30, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },
  gun120 = { kind = "shell", dmg = 640, speed = 4354, drop = 0.14, splash = 6, rate = 6.0, mag = 1, reload = 0, reserve = 30, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },
  gun105 = { kind = "shell", dmg = 480, speed = 4214, drop = 0.14, splash = 6, rate = 5.0, mag = 1, reload = 0, reserve = 36, range = 2600,
    vs = { inf = 0.8, light = 1.3, armor = 0.9, air = 0.8, ship = 0.6, fort = 1.1 }, fx = "tank", cal = 0.36 },
  -- 科技树换真模型的几型车的炮（用户 11-25「需要模型自己找」）：speed 是默认弹种（Ballistics.GUN 的第一种）的初速；rate 按真车装填：
  --   自动装弹机（T-80）7.1 秒一发，装填手装弹 6.5 秒（乘员「装填」技能再快）；reserve 真车的载弹量
  gun125u = { kind = "shell", dmg = 640, speed = 4802, drop = 0.14, splash = 6, rate = 7.1, mag = 1, reload = 0, reserve = 45, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },   -- T-80U 的 2A46M-1：3BM42「芒果」
  gun125b = { kind = "shell", dmg = 600, speed = 4788, drop = 0.14, splash = 6, rate = 7.1, mag = 1, reload = 0, reserve = 38, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },   -- T-80B 的 2A46-2：3BM22「别针」
  gun125a = { kind = "shell", dmg = 580, speed = 4998, drop = 0.14, splash = 6, rate = 7.1, mag = 1, reload = 0, reserve = 37, range = 2800,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },   -- T-64A 的 2A26M2：3BM15 尾翼稳定脱壳穿甲弹（1785 米 / 秒）
  gun120l55 = { kind = "shell", dmg = 680, speed = 4900, drop = 0.14, splash = 6, rate = 6.5, mag = 1, reload = 0, reserve = 42, range = 3200,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },   -- 豹 2A6 的 Rh-120 L/55：DM53（1750 米 / 秒）
  gun120l44 = { kind = "shell", dmg = 640, speed = 4620, drop = 0.14, splash = 6, rate = 6.5, mag = 1, reload = 0, reserve = 42, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },   -- 豹 2A4 的 Rh-120 L/44：DM33
  gun105l7 = { kind = "shell", dmg = 460, speed = 3993, drop = 0.14, splash = 6, rate = 6.5, mag = 1, reload = 0, reserve = 60, range = 2400,
    vs = { inf = 0.8, light = 1.3, armor = 0.9, air = 0.8, ship = 0.6, fort = 1.1 }, fx = "tank", cal = 0.36 },   -- 豹 1 的 L7A3：DM13 脱壳穿甲弹（1426 米 / 秒）
  gun105a5 = { kind = "shell", dmg = 480, speed = 4074, drop = 0.14, splash = 6, rate = 6.5, mag = 1, reload = 0, reserve = 55, range = 2800,
    vs = { inf = 0.8, light = 1.3, armor = 0.9, air = 0.8, ship = 0.6, fort = 1.1 }, fx = "tank", cal = 0.36 },   -- 豹 1A5 的 L7A3：DM33（105）尾翼稳定脱壳穿甲弹
  gun105m68 = { kind = "shell", dmg = 480, speed = 4183, drop = 0.14, splash = 6, rate = 6.5, mag = 1, reload = 0, reserve = 63, range = 2800,
    vs = { inf = 0.8, light = 1.3, armor = 0.9, air = 0.8, ship = 0.6, fort = 1.1 }, fx = "tank", cal = 0.36 },   -- M60A3 的 M68E1：M833 贫铀尾翼稳定脱壳穿甲弹
  gun105m60 = { kind = "shell", dmg = 460, speed = 4138, drop = 0.14, splash = 6, rate = 6.5, mag = 1, reload = 0, reserve = 63, range = 2400,
    vs = { inf = 0.8, light = 1.3, armor = 0.9, air = 0.8, ship = 0.6, fort = 1.1 }, fx = "tank", cal = 0.36 },   -- M60A1 的 M68：M392A2 脱壳穿甲弹
  -- 11-27 拆开重叠的版本（用户「把重叠的版本拆开（M1A2 / SEP / SEPv3 等）」）：M1 一族各自的炮——speed 是默认弹（Ballistics.GUN 的第一种）初速 × 2.8；
  --   装填同 M1A1 / M1A2 的 gun120（装填手 6 秒一发）；reserve 真车载弹量（M1 / IPM1 55 发、M1A1 40 发、M1A2 系 42 发，估的标「估」）
  gun105m1 = { kind = "shell", dmg = 480, speed = 4222, drop = 0.14, splash = 6, rate = 6.0, mag = 1, reload = 0, reserve = 55, range = 2800,
    vs = { inf = 0.8, light = 1.3, armor = 0.9, air = 0.8, ship = 0.6, fort = 1.1 }, fx = "tank", cal = 0.36 },   -- M1 的 M68A1 105 毫米：M774
  gun105ip = { kind = "shell", dmg = 480, speed = 4183, drop = 0.14, splash = 6, rate = 6.0, mag = 1, reload = 0, reserve = 55, range = 2800,
    vs = { inf = 0.8, light = 1.3, armor = 0.9, air = 0.8, ship = 0.6, fort = 1.1 }, fx = "tank", cal = 0.36 },   -- IPM1 的 M68A1：M833
  gun120a1 = { kind = "shell", dmg = 640, speed = 4676, drop = 0.14, splash = 6, rate = 6.0, mag = 1, reload = 0, reserve = 40, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },   -- 科技树 M1A1（1985）的 M256 120 毫米：M829（11-27 审查第 1 条）
  gun120hc = { kind = "shell", dmg = 640, speed = 4410, drop = 0.14, splash = 6, rate = 6.0, mag = 1, reload = 0, reserve = 40, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },   -- M1A1 HC 的 M256 120 毫米：M829A1
  gun120a2 = { kind = "shell", dmg = 640, speed = 4410, drop = 0.14, splash = 6, rate = 6.0, mag = 1, reload = 0, reserve = 42, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },   -- M1A2 的 M256：M829A1
  gun120sep = { kind = "shell", dmg = 640, speed = 4704, drop = 0.14, splash = 6, rate = 6.0, mag = 1, reload = 0, reserve = 42, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },   -- M1A2 SEP 的 M256：M829A2
  gun120sep3 = { kind = "shell", dmg = 640, speed = 4354, drop = 0.14, splash = 6, rate = 6.0, mag = 1, reload = 0, reserve = 42, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },   -- M1A2 SEPv3 的 M256 + 弹药数据链：M829A4
  -- M60A1 RISE 的 M68（M735，63 发）、豹 2A0 的 Rh-120 L/44（DM13，42 发）：装填同 M60A1 / 豹 2A4
  gun105m60r = { kind = "shell", dmg = 470, speed = 4203, drop = 0.14, splash = 6, rate = 6.5, mag = 1, reload = 0, reserve = 63, range = 2600,
    vs = { inf = 0.8, light = 1.3, armor = 0.9, air = 0.8, ship = 0.6, fort = 1.1 }, fx = "tank", cal = 0.36 },
  gun120l44a0 = { kind = "shell", dmg = 620, speed = 4620, drop = 0.14, splash = 6, rate = 6.5, mag = 1, reload = 0, reserve = 42, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },
  -- 96 式（ZPT-98：DTW-125 I 型，40 发估）、96A / 99 式（ZPT-98：DTW-125 II 型，41 发估）、T-90A（2A46M-2：3BM42，43 发）——都是自动装弹机，7.1 秒一发
  gun125c96 = { kind = "shell", dmg = 600, speed = 4844, drop = 0.14, splash = 6, rate = 7.1, mag = 1, reload = 0, reserve = 40, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },
  gun125c99 = { kind = "shell", dmg = 620, speed = 4928, drop = 0.14, splash = 6, rate = 7.1, mag = 1, reload = 0, reserve = 41, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },
  gun125m2 = { kind = "shell", dmg = 640, speed = 4802, drop = 0.14, splash = 6, rate = 7.1, mag = 1, reload = 0, reserve = 43, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },
  -- 59 式 / 69-II 式的 100 毫米线膛炮（用户 11-26「各系各阶段缺少的载具」：中国地面树一、二级）：59 式是 D-10T 的仿制（59 式 100 毫米坦克炮），
  --   手动装填 7～8 秒一发；69-II 式换了稳定器和激光测距、有尾翼稳定脱壳穿甲弹（Ballistics.GUN 里各自的弹）
  gun100d = { kind = "shell", dmg = 400, speed = 2484, drop = 0.18, splash = 6, rate = 7.5, mag = 1, reload = 0, reserve = 34, range = 2200,
    vs = { inf = 0.8, light = 1.3, armor = 0.9, air = 0.8, ship = 0.6, fort = 1.1 }, fx = "tank", cal = 0.34 },
  gun100d69 = { kind = "shell", dmg = 430, speed = 3962, drop = 0.16, splash = 6, rate = 7.0, mag = 1, reload = 0, reserve = 44, range = 2400,
    vs = { inf = 0.8, light = 1.3, armor = 0.9, air = 0.8, ship = 0.6, fort = 1.1 }, fx = "tank", cal = 0.34 },
  gun152 = { kind = "shell", dmg = 520, speed = 1912, drop = 0.3, splash = 8, rate = 7.5, mag = 1, reload = 0, reserve = 29, range = 2000,
    vs = { inf = 1.0, light = 1.3, armor = 0.9, air = 0.7, ship = 0.8, fort = 1.4 }, fx = "tank", cal = 0.43 },   -- M551 的 M81 152 毫米炮：M409 多用途破甲弹（683 米 / 秒，弹道弯）
  -- BMP-3 的 2A70 100 毫米低膛压线膛炮（用户 11-24 找的俄系）：3OF32 杀伤爆破榴弹，初速 250 米 / 秒、弹道很弯，打步兵、工事、轻装甲（炮射导弹 9M117 游戏里没有）
  gun100 = { kind = "shell", dmg = 330, speed = 700, drop = 0.42, splash = 9, rate = 6.0, mag = 1, reload = 0, reserve = 34, range = 2400,
    vs = { inf = 1.3, light = 1.1, armor = 0.4, air = 0.3, ship = 0.5, fort = 1.4 }, fx = "tank", cal = 0.3 },
  -- BMP-1 的 2A28「雷」73 毫米低压滑膛炮：PG-15V 火箭增程破甲弹（出膛 665 米 / 秒、火箭发动机再加速，平均按 1000 米 / 秒），自动装弹机 7.5 秒一发、40 发
  gun73 = { kind = "shell", dmg = 330, speed = 2800, drop = 0.3, splash = 5, rate = 7.5, mag = 1, reload = 0, reserve = 40, range = 1300,
    vs = { inf = 0.9, light = 1.3, armor = 0.85, air = 0.3, ship = 0.5, fort = 1.0 }, fx = "tank", cal = 0.26 },
  ac30 = { kind = "shell", dmg = 60, speed = 1150, drop = 0.2, splash = 4, rate = 0.19, mag = 50, reload = 4.5, reserve = 400, range = 2000,
    vs = { inf = 1, light = 1, armor = 0.22, air = 1.4, ship = 0.35, fort = 0.6 }, fx = "ac", cal = 0.2 },
  ac35 = { kind = "shell", dmg = 46, speed = 1300, drop = 0.15, splash = 5, rate = 0.07, mag = 120, reload = 5, reserve = 600, range = 2400,
    vs = { inf = 0.8, light = 0.8, armor = 0.1, air = 2.4, ship = 0.25, fort = 0.35 }, fx = "ac", cal = 0.2 },
  -- 87 式侦察警戒车的厄利空 KBA 25 毫米机关炮（日本制钢所特许生产；用户 11-27「很多缺的载具全部做一下」：日本「轻型」一列）：
  --   双路供弹，最高射速约 600 发 / 分；脱壳穿甲曳光弹初速 1335 米 / 秒（1 公里约 50 毫米）——速度按真弹换算成格（ac30 还是旧的游戏值）
  ac25 = { kind = "shell", dmg = 52, speed = 3738, drop = 0.15, splash = 3.5, rate = 0.1, mag = 100, reload = 6, reserve = 300, range = 2400,
    vs = { inf = 1, light = 1, armor = 0.2, air = 1.3, ship = 0.3, fort = 0.55 }, fx = "ac", cal = 0.18 },
  -- M2 / M2A2 布雷德利的 M242「大毒蛇」25 毫米链式炮（11-27 拆开重叠的版本）：双路供弹、常用 200 发 / 分（还有 100、500 发 / 分档）；
  --   M791 脱壳穿甲曳光弹 1345 米 / 秒（1 公里约 60 毫米，M919 贫铀是 1990 年代的）；炮塔里 300 发待发、车里 600 发备弹
  m242 = { kind = "shell", dmg = 52, speed = 3766, drop = 0.15, splash = 3.5, rate = 0.3, mag = 300, reload = 6, reserve = 600, range = 2400,
    vs = { inf = 1, light = 1, armor = 0.2, air = 1.3, ship = 0.3, fort = 0.55 }, fx = "ac", cal = 0.18 },
  -- M2A3 的 M242（11-27：原来写 30 毫米 ac30）：同一门炮、同样的射速和载弹，穿甲弹换成 M919 贫铀尾翼稳定脱壳穿甲曳光弹——
  --   初速 1385 米 / 秒（公开资料只有一份表格写 4544 英尺 / 秒，估）、穿深见 WtDamage.WPN.m242m919（估）；dmg / 打装甲倍数比 M791 高一点（估）
  m242m919 = { kind = "shell", dmg = 56, speed = 3878, drop = 0.15, splash = 3.5, rate = 0.3, mag = 300, reload = 6, reserve = 600, range = 2400,
    vs = { inf = 1, light = 1, armor = 0.24, air = 1.3, ship = 0.3, fort = 0.55 }, fx = "ac", cal = 0.18 },
  -- BRDM-2 的 KPVT 14.5 毫米重机枪（BPU-1 单人炮塔，一节弹链 50 发、车里一共 500 发，约 600 发 / 分；B-32 穿甲燃烧弹 500 米约 32 毫米）
  kpvt = { kind = "gun", dmg = 62, rate = 0.1, mag = 50, reload = 6, reserve = 450, range = 1600, spread = 0.4,
    vs = { inf = 1, light = 0.8, armor = 0.08, air = 0.6, ship = 0.1, fort = 0.25 }, fx = "lmg" },
  -- 铠甲-S1 的两门 2A38M 双管 30 毫米高炮（一门一分钟两千五百发，两门一起打）：打飞机为主，地面也能扫
  ac30aa = { kind = "shell", dmg = 44, speed = 1320, drop = 0.15, splash = 4.5, rate = 0.03, mag = 350, reload = 6, reserve = 1050, range = 2600,
    vs = { inf = 0.9, light = 0.8, armor = 0.12, air = 2.3, ship = 0.25, fort = 0.35 }, fx = "ac", cal = 0.2 },
  -- 铠甲-S1 的 57E6 地空导弹（两级、无线电指令制导：热诱弹骗不了）：要先用防空火控 Q 雷达锁住一架飞机（AaFcs.lua），服务器按 AirDefs.W.s57e6
  --   的速度、转弯飞（Armor.lua）；12 枚，打完回基地补
  s57e6 = { kind = "sam", dmg = 520, rate = 1.6, mag = 12, reload = 0, reserve = 0, range = 6000,
    vs = { inf = 0.3, light = 0.4, armor = 0.1, air = 1, ship = 0.2, fort = 0.1 }, fx = "msl" },
  -- 9K31「箭-1」的 9M31 地空导弹（用户 11-27「全部做一下」：俄罗斯「自行防空」一列）：红外导引头（热诱弹骗得了，Air.lua flare），
  --   发射架上四枚、车里不带备弹（打完回基地补）；也要 Q 锁住一架飞机才发（光学瞄准 + 导引头截获，游戏里同铠甲的防空火控）；
  --   射程按游戏的比例尺（57E6 真车约 20 公里 → 6000；9M31 约 4.2 公里，比针-V 还近）；飞行参数在 AirDefs.W.s9m31
  s9m31 = { kind = "sam", dmg = 380, rate = 3, mag = 4, reload = 0, reserve = 0, range = 2000,
    vs = { inf = 0.3, light = 0.3, armor = 0.05, air = 1, ship = 0.2, fort = 0.1 }, fx = "msl" },
  vulcan = { kind = "shell", dmg = 26, speed = 1200, drop = 0.2, splash = 2.5, rate = 0.035, mag = 300, reload = 6, reserve = 1200, range = 1600,
    vs = { inf = 1, light = 0.6, armor = 0.05, air = 2.0, ship = 0.15, fort = 0.25 }, fx = "ac", cal = 0.14 },
  -- 车顶 GAU-8 加特林附件（坦克改装，TankMods.OPT.gau8）：30 毫米，一秒二十发，2048 发
  gau8 = { kind = "shell", dmg = 52, speed = 1250, drop = 0.18, splash = 3.5, rate = 0.05, mag = 512, reload = 6, reserve = 1536, range = 2200,
    vs = { inf = 1, light = 1.1, armor = 0.32, air = 1.6, ship = 0.4, fort = 0.9 }, fx = "ac", cal = 0.22 },
  -- 反坦克导弹（用户 11-25「全部都做」⑥：战雷里步战车都带）：半自动有线制导——炮长十字线压着目标，导弹自己往瞄准线上靠（Armor.lua G.atgmStep）
  --   陶式 2A（布雷德利，发射箱两枚、车里再带五枚）：280 米 / 秒、3750 米、串联破甲 900 毫米；
  --   9M14「婴儿」（BMP-1，炮上导轨一枚、车里四枚）：120 米 / 秒、3000 米、400 毫米，又慢又难打
  tow2 = { kind = "atgm", dmg = 900, speed = 784, splash = 4, rate = 2.5, mag = 2, reload = 14, reserve = 5, range = 10500, fx = "msl", turn = 2.4 },
  malyutka = { kind = "atgm", dmg = 600, speed = 336, splash = 3, rate = 1, mag = 1, reload = 25, reserve = 4, range = 8400, fx = "msl", turn = 1.3 },
  konkurs = { kind = "atgm", dmg = 750, speed = 582, splash = 3, rate = 1, mag = 1, reload = 20, reserve = 4, range = 11200, fx = "msl", turn = 1.9 },   -- 9M113「竞技」：208 米 / 秒、4 公里、600 毫米（BMP-2）
  kornet = { kind = "atgm", dmg = 1000, speed = 840, splash = 4, rate = 2, mag = 2, reload = 18, reserve = 4, range = 15400, fx = "msl", turn = 2.2 },   -- 9M133「短号」：300 米 / 秒、5.5 公里、串联 1100 毫米（BMP-2M 的「海岸」战斗模块四联装）
  -- 11-27 拆开重叠的版本：M2（1981）的 BGM-71C 改进型陶式（单装药、不串联，约 600 毫米；278 米 / 秒、3750 米；发射箱两枚 + 车里五枚）、
  --   86 式的红箭-73（仿 9M14「婴儿」：约 425 毫米、120 米 / 秒、3 公里，炮上导轨一枚 + 车里四枚）
  tow1 = { kind = "atgm", dmg = 750, speed = 778, splash = 4, rate = 2.5, mag = 2, reload = 14, reserve = 5, range = 10500, fx = "msl", turn = 2.4 },
  hj73 = { kind = "atgm", dmg = 620, speed = 336, splash = 3, rate = 1, mag = 1, reload = 25, reserve = 4, range = 8400, fx = "msl", turn = 1.3 },
  coax = { kind = "gun", dmg = 24, rate = 0.08, mag = 200, reload = 5, reserve = 2000, range = 900, spread = 0.45,
    vs = { inf = 1, light = 0.15, armor = 0, air = 0.1, ship = 0, fort = 0.04 }, fx = "lmg" },
  hmg = { kind = "gun", dmg = 40, rate = 0.11, mag = 100, reload = 5, reserve = 900, range = 1200, spread = 0.5,
    vs = { inf = 1, light = 0.5, armor = 0.04, air = 0.4, ship = 0.05, fort = 0.12 }, fx = "lmg" },
  how155 = { kind = "arty", dmg = 340, splash = 26, rate = 7, mag = 1, reload = 0, reserve = 40, minR = 300, maxR = 3600, flight = 6,
    vs = { inf = 1, light = 1, armor = 0.6, air = 0, ship = 0.5, fort = 1.2 } },
  mlrs = { kind = "arty", dmg = 180, splash = 22, rate = 0.45, mag = 12, reload = 25, reserve = 24, minR = 500, maxR = 4000, flight = 7, scatter = 40,
    vs = { inf = 1, light = 1, armor = 0.45, air = 0, ship = 0.4, fort = 1 } },
}
-- 烟幕弹：每次齐射一组，落点约 30 格外，烟团半径 ~20 格、持续 30 秒
VehDefs.SMOKE = { range = 32, r = 20, life = 30, salvos = 2, reload = 12 }
-- 726 气垫艇：攻方不会游的车在登陆平台旁站在艇上生成，开车的人连艇一起开（服务器 Armor、客户端 Drive 共用）：
--   y 艇身中心高、deck 车底的高度、speed 水上最快（格 / 秒）、size 艇身、hp
VehDefs.LCAC = { y = 2.2, deck = 3.0, speed = 75, size = Vector3.new(28, 6, 48), hp = 1800 }   -- 75 格 / 秒：从登陆平台到海滩四十来秒

local D = {}
VehDefs.D = D

-- 履带车的公共部分（负重轮、履带）；轮式车的车轴
local function tracked(t)
  t.arch = "tracked"
  t.wheels = nil
  return t
end
local function wheeled(t)
  t.arch = "wheeled"
  return t
end
-- 同族的另一型（用户 11-25：科技树里一族车共用一个真模型，各自按真车给炮、弹、装甲、机动）：深拷一份再改，
--   嵌套的表（炮塔、炮、武器表）各自一份，后面按原模型改转轴、换机枪时不会互相改到
--   11-27（用户「把重叠的版本拆开（M1A2 / SEP / SEPv3 等）」「各维度还原一致」）：变型的 over 里写明
--     like = 同族那一型（借谁的模型）：按型号登记的表查不到这一型时退到它——驾驶界面的剪影（VehHud）、召唤卡片（Depot）、
--       坦克改装页（TankMods.FOR / ERADEF / PRESETS）、第一人称白名单（Config.FirstPerson.only）和车内（Interior.lua 的 ALIAS）；
--     noEra = true：借来的模型上有后来才加的爆反 / ARAT / TUSK 块（模型网格里自带的、默认贴的），这一型真车没有——
--       TankMods.eraOf 返回 nil：服务器 Era.lua 不装、客户端 VehModels 不另画、驾驶界面不画、改装页没有爆反格
--       （网格里烘焙着的那几块看得见、不起作用；另画的默认格都不画了）；
--     noStab = true：没有炮控稳定器（M60、59 式、豹 1 头一批：瞄准线跟着车体颠，Drive.lua 的 st.stab 开局就是关的）——
--       从没有稳定器的那一型拷出来、真车有稳定器的变型要写 noStab = false（深拷会把 true 一起拷过去）
local function dcopy(t)
  -- Vector3 这类值不拷（Roblox 里是 userdata；测试台里是带元表的表，拷了会丢元表）
  if type(t) ~= "table" or getmetatable(t) ~= nil then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = dcopy(v) end
  return o
end
local function variant(src, over)
  local t = dcopy(src)
  for k, v in pairs(over) do t[k] = v end
  return t
end

---------------------------------------------------------------- 坦克
-- 速度（用户 11-25「全部都做」⑦：原来车慢、加速太猛——M1A2 35 格 / 秒 ≈ 45 公里 / 时，加速 10 格 / 秒² ≈ 3.6 米 / 秒²，比真车快一倍）：
--   speed / rev 照真车的公路最高速、倒车速度换成格 / 秒（1 米 = 2.8 格：公里 / 时 ÷ 3.6 × 2.8）；accel ≈ 0.22 × 马力 / 吨（格 / 秒²）。
--   苏俄系倒车慢（T-72B3 约 4 公里 / 时、T-80U 11），北约的快（豹 2 31、M1 约 40）——战雷里也是这样

D.ztz99a = tracked({ cat = "tank", L = 22, W = 10.2, H = 7.4, hullH = 4.2, clear = 1.3, speed = 54.4, accel = 6.1, rev = 19.4, turn = 36,
  rw = { n = 6, r = 1.15, x = 4.0, z0 = -7.6, z1 = 7.2 }, era = true, skirt = true,
  turret = { pivot = V(0, 4.2, 0.6), size = V(7.4, 2.3, 8.2), style = "wedge", trav = 42, elev = { -6, 18 }, bustle = 2.2 },
  gun = { pivot = V(0, 0.9, -3.4), len = 14.5, cal = 0.46, brake = false, fume = true }, coax = V(1.1, 0.9, -3.6),
  sight = V(-1.9, 2.1, -2.6), cupola = V(1.7, 2.3, 0.6),   -- 车顶车长舱口一挺手动的 12.7 毫米重机枪（用户 11-21 晚：照真车加回，元数据 rws.mk = "manual"）
  smoke = { banks = { { at = V(3.3, 1.5, -1.6), yaw = 40 }, { at = V(-3.3, 1.5, -1.6), yaw = -40 } }, n = 4 },
  weapons = { "gun125", "coax" } })
-- 11-27 拆开重叠的版本（用户「把重叠的版本拆开」「各维度还原一致」）：科技树 99 式原来写 base（借 99A 的模型和性能：DTC10、二代热像）
-- 99 式（2001）：约 53 吨（估）、150HB 1500 马力（早期一说 1200）、公路 70 公里 / 时（估）；ZPT-98 125 毫米、DTW-125 II 型（DTC10 是 99A 才有的）、41 发；
--   炮长镜 5 / 11.4 倍（公开资料）、第一代热像；炮塔正面楔形附加装甲；JD-3 激光对抗、FY-4 爆反照 99A 能装（改装页照 99A，估）
D.ztz99base = variant(D.ztz99a, { like = "ztz99a", speed = 54.4, accel = 6.2, weapons = { "gun125c99", "coax" }, sightZoom = { day = { 5, 11.4 }, th = { 5, 11.4 } } })
-- 59 式中型坦克（用户 11-26「给各系各阶段缺少的载具都从 sketchfeb 上搞出来」：中国地面树一、二级原来空着；原模型 MMD_SonicNewYear，
--   tools/models/blveh.json type59）：T-54A 的国产型，36 吨、12150L 柴油机 520 马力（14.4 马力 / 吨）、公路 50 公里 / 时，倒车只有 6 公里 / 时上下；
--   59 式 100 毫米线膛炮（D-10T），手动装填；没有稳定器（行进间打不准：noStab，11-27 补上——原来只写在注释里，开出来照样带稳定器）、
--   没有夜视以外的观瞄；四人车组（装填手在右、舱口上一挺 12.7 高射机枪）。
--   尺寸、负重轮（五对，前后大间隔）、炮塔转轴、炮耳轴照模型量的（ImportedMeta type59）
D.type59 = tracked({ cat = "tank", L = 17.0, W = 9.2, H = 6.9, hullH = 3.9, clear = 1.2, speed = 38.9, accel = 3.2, rev = 4.7, turn = 30, noStab = true,
  rw = { n = 5, r = 1.15, x = 3.69, z0 = -5.9, z1 = 3.55 }, skirt = false,
  turret = { pivot = V(0.04, 3.87, -1.58), size = V(7.1, 2.3, 8.1), style = "round", trav = 16, elev = { -5, 17 }, bustle = 0 },
  gun = { pivot = V(0.1, 1.56, -1.71), len = 12.7, cal = 0.34, fume = true }, coax = V(0.9, 1.5, -2.2),
  sight = V(-1.1, 1.85, -2.0), cupola = V(1.3, 2.35, 0.3),
  smoke = { banks = { { at = V(3.0, 1.3, -1.6), yaw = 40 }, { at = V(-3.0, 1.3, -1.6), yaw = -40 } }, n = 2 },   -- 真车是发动机喷烟（TDA），游戏里按两组烟幕弹算
  sightZoom = { day = { 3.5, 7 }, th = { 3.5 } },   -- TSh-2B-32 炮长瞄准镜 3.5 / 7 倍；夜里主动红外
  weapons = { "gun100d", "coax" } })
-- 69-II 式（1982 出口型）：同一个车体、580 马力，炮控稳定器、激光测距、尾翼稳定脱壳穿甲弹；同一个模型（ImportedMeta 的 alias）
--   11-27：like = 59 式（HudIcons 只拍了 59 式：驾驶界面的剪影退到它）；有稳定器（noStab = false：59 式那一型是 true，深拷会拷过来）
D.type69 = variant(D.type59, { like = "type59", noStab = false, accel = 3.5, speed = 38.9, weapons = { "gun100d69", "coax" }, sightZoom = { day = { 3.5, 7 }, th = { 4 } } })
D.ztz96 = tracked({ cat = "tank", L = 20.5, W = 9.8, H = 7.0, hullH = 4.0, clear = 1.3, speed = 50.6, accel = 5.2, rev = 14.0, turn = 36,
  rw = { n = 6, r = 1.1, x = 3.85, z0 = -7.0, z1 = 6.7 }, era = true, skirt = true,
  turret = { pivot = V(0, 4.0, 0.4), size = V(6.8, 2.2, 7.0), style = "round", trav = 38, elev = { -6, 16 }, bustle = 1.2 },
  gun = { pivot = V(0, 0.9, -3.0), len = 14, cal = 0.45, fume = true }, coax = V(1.0, 0.9, -3.2),
  sight = V(-1.7, 2.0, -2.2), cupola = V(1.6, 2.2, 0.4),
  smoke = { banks = { { at = V(3.1, 1.4, -1.2), yaw = 40 }, { at = V(-3.1, 1.4, -1.2), yaw = -40 } }, n = 4 },
  weapons = { "gun125", "coax" } })
-- 11-27 拆开重叠的版本：科技树 96 式、96A 原来写 base（借 ztz96：它其实是 96B——43 吨、1000 马力、DTC10、三代热像、FY 爆反）
-- 96 式（1997）：41 吨、12150ZLA 730 马力、公路 57 公里 / 时（估）；ZPT-98 125 毫米、DTW-125 I 型、40 发（估）；激光测距 + 计算机、微光夜视；
--   没有爆反（模型上 96B 的 FY 块不起作用：noEra；era = false：没导入原模型、零件拼的时候也不画首上、炮塔的爆反块，同 T-80B）
D.ztz96base = variant(D.ztz96, { like = "ztz96", noEra = true, era = false, speed = 44.3, accel = 3.9, weapons = { "gun125c96", "coax" } })
-- 96A（2006）：42.8 吨、800 马力（另说 865，估）、公路 65 公里 / 时；DTW-125 II 型、41 发；数字火控（猎歼）、第二代热像；
--   箭形 FY-4 爆反（改装页默认 FY-4，TankMods.FOR.ztz96a；96B 同样默认 FY-4，见 TankMods）
D.ztz96a = variant(D.ztz96, { like = "ztz96", speed = 50.6, accel = 4.1, weapons = { "gun125c99", "coax" } })
-- T-90M「突破-3」（用户 11-24「没事干了就去找俄系」）：46.5 吨、V-92S2F 1130 马力、公路 60 公里 / 时；2A46M-5 125 毫米滑膛炮、转盘式自动装弹机（22 发）；
--   三人车组：炮长左、车长右（同 99A）；炮塔正面、侧面、首上、侧裙板都是「化石」（Relikt）重型爆反；原模型 mansoorsajidp（带车内）
D.t90m = tracked({ cat = "tank", L = 20.5, W = 10.2, H = 6.4, hullH = 4.4, clear = 1.3, speed = 46.7, accel = 5.3, rev = 4.7, turn = 36,
  rw = { n = 6, r = 1.14, x = 3.93, z0 = -6.7, z1 = 5.4 }, era = true, skirt = true,
  turret = { pivot = V(0, 4.3, 0.34), size = V(7.0, 2.0, 7.4), style = "round", trav = 40, elev = { -6, 14 }, bustle = 1.6 },
  gun = { pivot = V(0, 1.28, -2.31), len = 14, cal = 0.45, fume = true }, coax = V(1.0, 0.9, -3.0),
  sight = V(-1.8, 2.0, -2.0), cupola = V(1.6, 2.1, 0.4),
  smoke = { banks = { { at = V(3.2, 1.3, -1.6), yaw = 40 }, { at = V(-3.2, 1.3, -1.6), yaw = -40 } }, n = 6 },
  sightZoom = { day = { 4, 12 }, th = { 3.7, 12 } },   -- 「松树-U」炮长瞄准镜：昼光 4 / 12 倍，热像（Catherine-FC）宽 3.7、窄 12 倍
  weapons = { "gun125r", "coax" } })
-- T-90A（2004，11-27 拆开重叠的版本：原来写 base 借 T-90M）：46.5 吨、V-92S2 1000 马力、60 公里 / 时；2A46M-2 125 毫米（2006 年以后换 2A46M-5）、
--   3BM42「芒果」/ 3BK31 / 3OF26 / 9M119M「反射」、43 发；焊接炮塔、接触-5（模型上 T-90M 的块照用，改装页照 T-90M）；
--   1A45T「额尔齐斯」火控、1G46M 炮长镜（昼光 2.7–12 倍）、ESSA 热像（二代，4 / 12 倍，估）；「窗帘-1」光电对抗
D.t90a = variant(D.t90m, { like = "t90m", speed = 46.7, accel = 4.7, weapons = { "gun125m2", "coax" }, sightZoom = { day = { 2.7, 12 }, th = { 4, 12 } } })
-- T-80U（用户 11-25「需要模型自己找」：科技树 T-80 一族原来借 T-90M，换成真 T-80U）：46 吨、GTD-1250 燃气轮机 1250 马力、公路 70 公里 / 时
--   （起步、加速是苏系里最快的）；2A46M-1 125 毫米滑膛炮、「篮子」式自动装弹机（28 发）、3BM42「芒果」脱壳穿甲弹；炮塔正面、首上挂「接触-5」
--   重型爆反（原模型上就有，EraMeta）；三人车组：炮长左、车长右；原模型 javanilga
D.t80u = tracked({ cat = "tank", turbine = true, L = 19.6, W = 10.1, H = 6.2, hullH = 3.9, clear = 1.3, speed = 54.4, accel = 6.0, rev = 8.6, turn = 38,
  rw = { n = 6, r = 0.95, x = 3.95, z0 = -6.05, z1 = 5.41 }, era = true, skirt = true,
  turret = { pivot = V(0, 3.73, -0.77), size = V(7.6, 2.0, 7.2), style = "round", trav = 36, elev = { -5, 14 }, bustle = 1.2 },
  gun = { pivot = V(0, 0.65, -2.63), len = 13.7, cal = 0.45, fume = true }, coax = V(1.1, 0.65, -3.0),
  sight = V(-2.0, 1.9, -2.4), cupola = V(3.0, 2.6, -0.3),
  smoke = { banks = { { at = V(3.3, 1.3, -1.8), yaw = 40 }, { at = V(-3.3, 1.3, -1.8), yaw = -40 } }, n = 4 },
  sightZoom = { day = { 3.6, 12 }, th = { 5.5 } },   -- 1G46 炮长瞄准镜：昼光 3.6–12 倍；夜视「布兰-PA」5.5 倍
  weapons = { "gun125u", "coax" } })
-- T-80B（1978）：42.5 吨、GTD-1000TF 1100 马力；2A46-2 炮、3BM22「别针」；还没有爆反（模型是 T-80U，科技树上写「同族模型」）；TPD-K1 瞄准镜 8 倍
--   11-27：借来的 T-80U 模型上的 22 格接触-5 原来照样起作用（TankMods.eraOf 按模型拿 EraMeta）——noEra 挡住
D.t80b = variant(D.t80u, { like = "t80u", noEra = true, speed = 54.4, accel = 5.7, rev = 8.6, era = false, weapons = { "gun125b", "coax" }, sightZoom = { day = { 8 }, th = { 5.5 } } })
-- T-80BVM（2018）：T-80B 的大改，GTD-1250TF 1250 马力、2A46M-4 炮打 3BM60「铅-2」、「化石」重型爆反、「松树-U」热像瞄准镜
D.t80bvm = variant(D.t80u, { weapons = { "gun125r", "coax" }, sightZoom = { day = { 4, 12 }, th = { 3.7, 12 } } })
-- T-64A / T-64B（用户 11-25「还有很多没有建模」：原来借 T-80B，换成真 T-64，原模型 MirzaArrafiERV_45）：哈尔科夫的第一代苏联主战坦克，
--   38 吨、5TDF 两冲程对置活塞柴油机 700 马力、公路 60 公里 / 时，倒车很慢（4 公里 / 时）；自动装弹机、三人车组（炮长在左、车长在右）；
--   首上是钢 + 玻璃钢的复合装甲（K 型），炮塔铸钢里夹铝；尺寸、负重轮、转轴、炮耳轴照模型量的（ImportedMeta t64）
D.t64a = tracked({ cat = "tank", L = 18.3, W = 9.2, H = 6.7, hullH = 4.2, clear = 1.4, speed = 46.7, accel = 4.1, rev = 3.2, turn = 36,
  rw = { n = 6, r = 0.82, x = 3.54, z0 = -5.52, z1 = 5.88 }, skirt = true,
  turret = { pivot = V(0, 3.68, 0.53), size = V(7.4, 2.0, 7.0), style = "round", trav = 30, elev = { -6, 14 }, bustle = 1.0 },
  gun = { pivot = V(0, 0.87, -3.02), len = 14.1, cal = 0.45, fume = true }, coax = V(1.1, 0.87, -3.3),
  sight = V(-2.0, 1.9, -2.6), cupola = V(2.9, 2.5, -0.2),
  smoke = { banks = { { at = V(3.2, 1.3, -1.6), yaw = 40 }, { at = V(-3.2, 1.3, -1.6), yaw = -40 } }, n = 4 },
  sightZoom = { day = { 8 }, th = { 5.5 } },   -- TPD-2-49 炮长瞄准镜 8 倍；TPN-1-49-23 夜视 5.5 倍（主动红外）
  weapons = { "gun125a", "coax" } })
-- T-64B（1976）：39 吨、同一台 700 马力；2A46-2 炮、3BM22「别针」，1G42 激光测距瞄准镜（3.9～9.5 倍）、新的火控计算机
--   （9M112「眼镜蛇」炮射导弹游戏里没有）；首上、炮塔正面加厚
D.t64b = variant(D.t64a, { accel = 4.0, weapons = { "gun125b", "coax" }, sightZoom = { day = { 3.9, 9.5 }, th = { 5.5 } } })
-- 74 式（用户 11-25「还有很多没有建模」：原来借豹 1，换成真 74 式，原模型 jonathanto99）：陆上自卫队第一代自研主战坦克，38 吨、
--   三菱 10ZF 风冷柴油机 720 马力、公路 53 公里 / 时；油气悬挂能整车升降、前后左右俯仰（炮俯角大）；L7 系列 105 毫米线膛炮，
--   75 式脱壳穿甲弹；激光测距、弹道计算机；四人车组（炮长、车长在右）；尺寸、负重轮、转轴、炮耳轴照模型量的（ImportedMeta type74）
D.type74 = tracked({ cat = "tank", L = 18.5, W = 9.0, H = 7.2, hullH = 4.6, clear = 1.8, speed = 41.2, accel = 4.2, rev = 15.6, turn = 38,
  rw = { n = 5, r = 1.1, x = 3.49, z0 = -5.29, z1 = 4.81 }, skirt = false,
  turret = { pivot = V(-0.08, 4.28, -0.88), size = V(7.6, 2.2, 7.8), style = "round", trav = 32, elev = { -12, 15 }, bustle = 1.8 },
  gun = { pivot = V(0, 0.4, -4.62), len = 9.9, cal = 0.36, fume = true }, coax = V(-0.9, 0.4, -4.4),
  sight = V(1.7, 1.9, -2.4), cupola = V(1.8, 2.6, 0.6),
  smoke = { banks = { { at = V(3.4, 1.4, -1.0), yaw = 40 }, { at = V(-3.4, 1.4, -1.0), yaw = -40 } }, n = 3 },
  sightZoom = { day = { 8 }, th = { 8 } },   -- J2 炮长瞄准镜 8 倍；夜里是主动红外（炮塔左边的大探照灯）
  weapons = { "gun105l7", "coax" } })
-- 74 式改（1993）：38.7 吨；热像仪、侧裙板、93 式尾翼稳定脱壳穿甲弹（游戏里按 DM33（105）算）
D.type74g = variant(D.type74, { skirt = true, accel = 4.1, weapons = { "gun105a5", "coax" }, sightZoom = { day = { 8 }, th = { 8 } } })
-- 猎豹（用户 11-25「还有很多没有建模」：原来借 PGZ-07，换成真猎豹，原模型 Scout）：豹 1 底盘、47.5 吨、MTU MB 838 830 马力、公路 65 公里 / 时；
--   炮塔两侧各一门 35 毫米厄利空 KDA（每门 550 发 / 分），后面的搜索雷达一直转、前面的跟踪雷达；三人车组；
--   尺寸、负重轮、转轴照模型量的（炮耳轴给在炮舱中间，ImportedMeta gepard）
D.gepard1a1 = tracked({ cat = "aa", L = 20.5, W = 9.1, H = 9.2, hullH = 4.6, clear = 1.2, speed = 50.6, accel = 3.9, rev = 19.4, turn = 40,
  rw = { n = 7, r = 0.89, x = 3.63, z0 = -6.65, z1 = 4.8 }, skirt = true,
  turret = { pivot = V(0, 1.89, -2.41), size = V(7.0, 3.0, 8.4), style = "spaag", trav = 90, elev = { -10, 85 }, radar = true, twin = 4.7 },
  gun = { pivot = V(0, 4.61, 1.04), len = 9.9, cal = 0.24 }, sight = V(0, 5.4, -1.4),
  smoke = { banks = { { at = V(3.0, 4.6, -4.4), yaw = 35 }, { at = V(-3.0, 4.6, -4.4), yaw = -35 } }, n = 4 },
  weapons = { "ac35" } })
-- 猎豹 1A2（1998）：新的火控计算机、热像仪、新的脱壳穿甲弹（FAPDS），雷达升级
D.gepard1a2 = variant(D.gepard1a1, { accel = 3.8 })
-- BMP-2（用户 11-25「还有很多没有建模」：原来借 BMP-1，换成真 BMP-2，原模型 Scout）：14.3 吨、UTD-20 300 马力、公路 65 公里 / 时、能浮渡；
--   双人炮塔：2A42 30 毫米机关炮、PKT 并列机枪、炮塔顶上 9M113「竞技」反坦克导弹（半自动有线制导）；后面坐 7 个步兵；
--   尺寸、负重轮、转轴照模型量的（炮耳轴给在防盾里，ImportedMeta bmp2）
D.bmp2 = tracked({ cat = "apc", L = 18.9, W = 8.7, H = 6.9, hullH = 5.1, clear = 1.2, speed = 50.6, accel = 4.6, rev = 7.8, turn = 40, amphib = true, boat = true,
  rw = { n = 6, r = 0.84, x = 3.63, z0 = -3.85, z1 = 5.64 }, skirt = false,
  turret = { pivot = V(0.11, 1.66, 2.41), size = V(5.2, 1.6, 5.2), style = "ifv", trav = 35, elev = { -5, 74 } },
  gun = { pivot = V(-0.02, 3.81, -2.55), len = 5.8, cal = 0.18 }, coax = V(0.5, 3.6, -2.3),
  sight = V(-1.0, 4.4, -1.0),
  smoke = { banks = { { at = V(2.2, 4.0, 0.8), yaw = 40 }, { at = V(-2.2, 4.0, 0.8), yaw = -40 } }, n = 3 },
  sightZoom = { day = { 6 }, th = { 5.3 } },   -- BPK-1-42 炮长瞄准镜：昼光 6 倍、夜视 5.3 倍
  weapons = { "ac30", "konkurs", "coax" }, seats = 8 })
-- BMP-2M（2000 年代）：「海岸」战斗模块——同一门 2A42，炮塔两侧四联装 9M133「短号」，BPK-3-42 热像瞄准镜（模型还是 BMP-2 的炮塔，科技树写「同族模型」）
D.bmp2m = variant(D.bmp2, { weapons = { "ac30", "kornet", "coax" }, sightZoom = { day = { 4, 12 }, th = { 3.6, 12 } } })
-- 豹 2A6（用户 11-25「需要模型自己找」：原来借 M1A2）：59.9 吨、MTU MB 873 1500 马力、公路 72 公里 / 时；莱茵金属 Rh-120 L/55 120 毫米滑膛炮、
--   DM53 钨合金尾翼稳定脱壳穿甲弹；炮塔正面楔形附加装甲；四人车组：炮长、车长在右，装填手在左（并列机枪在炮左边）；原模型 mansoorsajidp
D.leo2a6 = tracked({ cat = "tank", L = 22.4, W = 10.5, H = 8.4, hullH = 5.3, clear = 1.5, speed = 56.0, accel = 5.3, rev = 24.1, turn = 36,
  rw = { n = 7, r = 1.15, x = 3.78, z0 = -7.28, z1 = 6.93 }, era = false, skirt = true,
  turret = { pivot = V(0, 4.69, -3.08), size = V(8.8, 2.5, 10.0), style = "wedge", trav = 40, elev = { -9, 20 }, bustle = 2.8 },
  gun = { pivot = V(0, 0.87, -3.62), len = 12.1, cal = 0.42 }, coax = V(-1.0, 0.87, -3.6),
  sight = V(2.0, 2.4, -3.2), cupola = V(1.8, 3.0, 1.0),
  smoke = { banks = { { at = V(4.2, 2.0, 1.5), yaw = 60 }, { at = V(-4.2, 2.0, 1.5), yaw = -60 } }, n = 8 },
  sightZoom = { day = { 3, 12 }, th = { 3, 12 } },   -- EMES-15 炮长主瞄准镜：昼光 3 / 12 倍，WBG-X 热像 3 / 12 倍
  weapons = { "gun120l55", "coax" } })
-- 豹 2A7V（用户 11-25「坦克单独找建模很多坦克没有建模」：原来借 2A6，换成真模型，MirzaArrafiERV_45）：66.5 吨、1500 马力、公路 68 公里 / 时；
--   Rh-120 L/55A1（游戏里按 DM53 算）；炮塔、车体加了新一代模块装甲，车顶有遥控武器站；转轴、炮耳轴照模型量的（ImportedMeta leo2a7v）
D.leo2a7v = variant(D.leo2a6, { L = 22.0, W = 10.3, H = 8.6, hullH = 4.5, speed = 52.9, accel = 5.0, rev = 24.1,
  turret = { pivot = V(0.03, 4.5, -1.8), size = V(8.8, 2.6, 10.6), style = "wedge", trav = 40, elev = { -9, 20 }, bustle = 3.0 },
  gun = { pivot = V(-0.03, 0.88, -5.47), len = 12.3, cal = 0.42 }, coax = V(-1.0, 0.88, -5.2),
  weapons = { "gun120l55", "coax" } })
-- 豹 2A4（1985）：55 吨、同一台 1500 马力；Rh-120 L/44 炮、DM33；炮塔是直立的复合装甲（模型是 2A6 的楔形，科技树上写「暂用」）
D.leo2a4 = variant(D.leo2a6, { speed = 56.0, accel = 6.0, rev = 24.1, weapons = { "gun120l44", "coax" } })
-- 11-27 拆开重叠的版本（用户「把重叠的版本拆开」「各维度还原一致」）：科技树豹 2A0、豹 2A5 原来写 base（借 2A4 / 2A6 的模型和性能）
-- 豹 2A0（1979）：55.2 吨（估）、MB 873 1500 马力、公路 72 公里 / 时（同 2A4：早期豹 2 是 55.15 吨、72 公里 / 时；68 只见于加拿大的变型页，
--   11-27 审查改的）；Rh-120 L/44、DM13（120 毫米第一代尾翼稳定脱壳）/ DM12；
--   第一代复合装甲（直立炮塔，模型是 2A6 的楔形）；EMES 15 激光测距 + 计算机；夜里是 PZB 200 微光（WBG-X 热像是后几批才装的）
D.leo2a0 = variant(D.leo2a6, { like = "leo2a6", speed = 56.0, accel = 6.0, rev = 24.1, weapons = { "gun120l44a0", "coax" } })
-- 豹 2A5（1995）：59.5 吨（估）、1500 马力、72 公里 / 时；炮塔楔形附加装甲（同 2A6），炮还是 L/44（L/55 是 2A6 才换的）、DM33；车长 PERI-R17A2 热像（猎歼）
D.leo2a5 = variant(D.leo2a6, { like = "leo2a6", speed = 56.0, accel = 5.5, rev = 24.1, weapons = { "gun120l44", "coax" } })
-- 豹 1（用户 11-25「需要模型自己找」：原来借 M10）：40 吨、MTU MB 838 830 马力、公路 65 公里 / 时；L7A3 105 毫米线膛炮、DM13 脱壳穿甲弹；
--   装甲薄（首上 70 毫米斜置）、跑得快；四人车组：炮长、车长在右；原模型 FlashPoin（原贴图是没上漆的灰，按联邦国防军黄橄榄色调过）
--   11-27：这一型是科技树 de_leo1（1965 年头一批）——头一批的炮没有稳定器（noStab），凯迪拉克 - 盖奇双向稳定器是 1A1 才加的
D.leo1 = tracked({ cat = "tank", L = 19.5, W = 9.3, H = 7.0, hullH = 4.3, clear = 1.2, speed = 50.6, accel = 4.6, rev = 19.4, turn = 40, noStab = true,
  rw = { n = 7, r = 0.91, x = 3.78, z0 = -6.5, z1 = 5.3 }, skirt = true,
  turret = { pivot = V(0, 4.33, -1.73), size = V(7.2, 2.4, 7.6), style = "round", trav = 40, elev = { -9, 20 }, bustle = 1.6 },
  gun = { pivot = V(0, 1.09, -2.84), len = 12.4, cal = 0.36, fume = true }, coax = V(-0.9, 1.0, -3.0),
  sight = V(1.6, 2.0, -2.2), cupola = V(1.6, 2.4, 0.4),
  smoke = { banks = { { at = V(3.3, 1.6, 0.6), yaw = 60 }, { at = V(-3.3, 1.6, 0.6), yaw = -60 } }, n = 4 },
  sightZoom = { day = { 8 }, th = { 8 } },   -- TZF 1A 炮长瞄准镜 8 倍（没有热像，夜里照红外探照灯）
  weapons = { "gun105l7", "coax" } })
-- 豹 1A1A1（1975，11-27 拆开重叠的版本：原来写 base 借豹 1）：42.4 吨、MB 838 CaM-500 830 马力、65 公里 / 时；炮塔加了 Blohm + Voss 的间隙装甲（约 +760 千克）；
--   L7A3、DM13 脱壳穿甲弹（DM23 尾翼稳定脱壳 1979 年以后才有）；TEM 2A 体视测距仪（没有激光）、稳定器（1A1 起：noStab = false）；夜里主动红外（PZB 200 微光是 1A1A2 才有）
D.leo1a1a1 = variant(D.leo1, { like = "leo1", noStab = false, speed = 50.6, accel = 4.3, rev = 19.4 })
-- 豹 1A5（1987）：42.4 吨；EMES 18 火控、WBG-X 热像，打 DM33（105）尾翼稳定脱壳穿甲弹；炮塔加了间隙装甲；有稳定器
D.leo1a5 = variant(D.leo1, { noStab = false, speed = 50.6, accel = 4.3, rev = 19.4, weapons = { "gun105a5", "coax" }, sightZoom = { day = { 3, 12 }, th = { 3, 12 } } })
-- M60A3 TTS（用户 11-25「需要模型自己找」：原来借 M10）：52.6 吨、AVDS-1790-2C 750 马力柴油机、公路 48 公里 / 时（慢）；M68E1 105 毫米线膛炮、
--   M833 贫铀脱壳穿甲弹，激光测距、弹道计算机、AN/VSG-2 坦克热像瞄准镜（TTS）；四人车组：炮长、车长在右；原模型 jonathanto99（按美军森林绿改色）
D.m60a3 = tracked({ cat = "tank", L = 19.8, W = 10.1, H = 8.2, hullH = 4.5, clear = 1.3, speed = 37.3, accel = 3.1, rev = 13.2, turn = 34,
  rw = { n = 6, r = 0.95, x = 3.92, z0 = -6.03, z1 = 6.32 }, skirt = false,
  turret = { pivot = V(0, 4.48, -1.64), size = V(8.4, 2.6, 9.0), style = "round", trav = 24, elev = { -10, 20 }, bustle = 2.4 },
  gun = { pivot = V(0.1, 1.16, -2.85), len = 11.8, cal = 0.36, fume = true }, coax = V(-0.9, 1.1, -3.0),
  sight = V(1.9, 1.9, -2.6), cupola = V(1.9, 3.3, 0.6),
  smoke = { banks = { { at = V(3.8, 1.5, -1.6), yaw = 40 }, { at = V(-3.8, 1.5, -1.6), yaw = -40 } }, n = 6 },
  sightZoom = { day = { 8 }, th = { 4, 12 } },   -- M35E1 昼光 8 倍；AN/VSG-2 热像宽 4、窄 12 倍
  weapons = { "gun105m68", "coax" } })
-- 10 式（用户 11-25「坦克单独找建模很多坦克没有建模」：原来借 M1A2，换成真模型，MirzaArrafiERV_45）：44 吨、1200 马力、公路 70 公里 / 时，
--   无级变速，倒车跟前进一样快；120 毫米 L/44 滑膛炮、尾舱自动装弹机，三人车组；模块化复合装甲；转轴、炮耳轴照模型量的（ImportedMeta type10）
D.type10 = tracked({ cat = "tank", L = 21.7, W = 9.7, H = 7.4, hullH = 4.1, clear = 1.3, speed = 54.4, accel = 6.0, rev = 54.4, turn = 38,
  rw = { n = 5, r = 1.1, x = 3.8, z0 = -6.4, z1 = 5.4 }, skirt = true,
  turret = { pivot = V(0.01, 4.14, -0.55), size = V(8.6, 2.4, 10.0), style = "wedge", trav = 40, elev = { -8, 15 }, bustle = 3.2 },
  gun = { pivot = V(-0.01, 1.09, -7.68), len = 7.8, cal = 0.42 }, coax = V(1.0, 1.0, -7.2),
  sight = V(1.9, 2.0, -3.0), cupola = V(-1.6, 2.6, 0.6),
  smoke = { banks = { { at = V(3.4, 1.6, -2.0), yaw = 40 }, { at = V(-3.4, 1.6, -2.0), yaw = -40 } }, n = 4 },
  sightZoom = { day = { 3, 12 }, th = { 3, 12 } },
  weapons = { "gun120l44", "coax" } })
-- M551 谢里登（用户 11-25「坦克单独找建模很多坦克没有建模」：原来借豹 1，换成真模型，MirzaArrafiERV_45）：15.2 吨、6V53T 300 马力、
--   公路 70 公里 / 时、能浮渡；铝合金车体、钢炮塔，装甲很薄；M81 152 毫米炮 / 导弹发射器（M409 多用途破甲弹；MGM-51 导弹游戏里没有）；四人车组
D.m551 = tracked({ cat = "tank", L = 18.2, W = 8.0, H = 7.5, hullH = 4.5, clear = 1.3, speed = 54.4, accel = 4.3, rev = 15.6, turn = 42,
  rw = { n = 5, r = 1.03, x = 3.29, z0 = -6.0, z1 = 3.94 }, skirt = false,
  turret = { pivot = V(0, 4.54, -0.1), size = V(7.4, 2.9, 9.0), style = "round", trav = 30, elev = { -8, 19 }, bustle = 1.6 },
  gun = { pivot = V(0, 0.77, -3.74), len = 5.3, cal = 0.43 }, coax = V(0.6, 0.6, -3.6),
  sight = V(-1.5, 1.7, -2.2), cupola = V(1.5, 2.6, 0.4),
  smoke = { banks = { { at = V(3.0, 1.3, -1.4), yaw = 40 }, { at = V(-3.0, 1.3, -1.4), yaw = -40 } }, n = 4 },
  sightZoom = { day = { 8 }, th = { 8 } },   -- M127 / M129 炮长瞄准镜 8 倍（没有热像）
  weapons = { "gun152", "coax" } })
-- M60A1（1962）：49.7 吨、750 马力；M68 炮打 M392A2 脱壳穿甲弹，合像式测距、没有热像（模型是 M60A3，科技树上写「暂用」）
D.m60a1 = variant(D.m60a3, { speed = 37.3, accel = 3.4, rev = 13.2, weapons = { "gun105m60", "coax" }, sightZoom = { day = { 8 }, th = { 8 } } })
-- 11-27 拆开重叠的版本（用户「把重叠的版本拆开」「各维度还原一致」）：科技树 M60、M60A1 RISE 原来写 base（借 M60A1 的模型和性能）
-- M60（1960）：46.3 吨、AVDS-1790-2 750 马力、48 公里 / 时；M68 105 毫米（M392 脱壳 / M456 破甲）；M48 式的短炮塔（长鼻子炮塔是 M60A1 才换的）；
--   M17 合像测距仪 + 机械弹道计算机（没有激光）；没有炮控稳定器（noStab：瞄准线跟着车体颠；M60A1 1972 年起才加装 AOS 稳定器）；AN/VSS-1 红外探照灯
D.m60 = variant(D.m60a1, { like = "m60a3", noStab = true, speed = 37.3, accel = 3.6, rev = 13.2 })
-- M60A1 RISE（1977，Reliability Improved Selected Equipment）：约 50.5 吨（估）、AVDS-1790-2C 750 马力；M735 钨合金尾翼稳定脱壳穿甲弹（1978）；
--   还是合像测距（激光测距是 M60A3 才有）、加装稳定器；RISE Passive 型被动微光夜视
D.m60a1rise = variant(D.m60a1, { like = "m60a3", speed = 37.3, accel = 3.3, rev = 13.2, weapons = { "gun105m60r", "coax" } })
D.m1a2 = tracked({ cat = "tank", turbine = true, L = 23, W = 10.2, H = 7.6, hullH = 4.2, clear = 1.4, speed = 52.1, accel = 5.2, rev = 29.6, turn = 35,
  rw = { n = 7, r = 1.05, x = 4.0, z0 = -7.8, z1 = 7.6 }, era = false, skirt = true, tusk = false,
  turret = { pivot = V(0, 4.2, 0.9), size = V(7.8, 2.4, 9.4), style = "abrams", trav = 42, elev = { -9, 20 }, bustle = 3.0 },
  gun = { pivot = V(0, 0.95, -4.0), len = 14, cal = 0.44 }, coax = V(1.2, 0.95, -4.1),
  sight = V(1.75, 2.2, -2.8), cupola = V(1.8, 2.4, 0.8), citv = V(-1.4, 2.6, -0.4),   -- 主瞄准镜在炮右边（炮长坐右边）
  -- 主瞄准镜的倍率（Drive.lua 的视场档）：SEPv2 第二代前视红外热像宽视场 3 / 6 倍、窄视场 13 / 25 / 50 倍；昼光通道 3 / 10 倍
  sightZoom = { day = { 3, 10 }, th = { 3, 6, 13, 25, 50 } },
  smoke = { banks = { { at = V(3.5, 1.6, -2.4), yaw = 35 }, { at = V(-3.5, 1.6, -2.4), yaw = -35 } }, n = 6 },
  weapons = { "gun120", "coax" } })
D.m1a1 = tracked({ cat = "tank", turbine = true, L = 22.5, W = 10.2, H = 7.4, hullH = 4.2, clear = 1.4, speed = 52.1, accel = 5.8, rev = 29.6, turn = 35,
  rw = { n = 7, r = 1.05, x = 4.0, z0 = -7.6, z1 = 7.4 }, era = false, skirt = true,
  turret = { pivot = V(0, 4.2, 0.9), size = V(7.6, 2.3, 9.0), style = "abrams", trav = 40, elev = { -9, 20 }, bustle = 2.6 },
  gun = { pivot = V(0, 0.95, -3.9), len = 14, cal = 0.44 }, coax = V(1.2, 0.95, -4.0),
  sight = V(1.75, 2.1, -2.7), cupola = V(1.8, 2.3, 0.8),
  smoke = { banks = { { at = V(3.4, 1.5, -2.3), yaw = 35 }, { at = V(-3.4, 1.5, -2.3), yaw = -35 } }, n = 6 },
  sightZoom = { day = { 3, 10 }, th = { 3, 10 } },   -- M1A1 主瞄准镜：昼光 3 / 10 倍，热像（第一代）宽 3 倍、窄 10 倍
  weapons = { "gun120", "coax" } })
-- 11-27 拆开重叠的版本（用户「把重叠的版本拆开（M1A2 / SEP / SEPv3 等）」「各维度还原一致」）：科技树 M1 一族原来六项写 base（模型、性能都借 M1A1 / M1A2 SEPv2），
--   现在各是各的型号：炮、弹、装甲（WtDamage.PROF）、车重 → 加速、观瞄照年代，模型照旧借同族的（ImportedMeta 的 alias）。车重、马力、公路速度是公开资料，拿不准的标「估」；
--   燃气轮机、炮塔转轴、车长独立热像（CITV：M1A2 起）从同族继承；M1～M1A2 SEP 模型上的 ARAT 侧裙（TUSK，2006 年以后）不起作用（noEra）
-- M1（1980）：54.4 吨（60 短吨）、AGT1500 1500 马力、公路限速 72 公里 / 时；M68A1 105 毫米线膛炮（M774 贫铀尾翼稳定脱壳）、55 发；
--   第一代伯灵顿（乔巴姆）复合装甲；炮长 GPS 昼光 3 / 10 倍 + 第一代热像 3 / 10 倍、激光测距 + M21 弹道计算机；没有 CITV
D.m1 = variant(D.m1a1, { like = "m1a1", noEra = true, speed = 56.0, accel = 6.1, weapons = { "gun105m1", "coax" } })
-- IPM1（1984）：55.7 吨（61.4 短吨）；炮塔正面加厚、M833 贫铀脱壳穿甲弹；其余同 M1
D.m1ip = variant(D.m1a1, { like = "m1a1", noEra = true, speed = 56.0, accel = 5.9, weapons = { "gun105ip", "coax" } })
-- 科技树的 M1A1（1985，11-27 审查第 1 条：原来科技树直接开 D.m1a1——打 2003 年的 M829A3、带 ARAT 侧裙和 TUSK / Trophy 改装页，
--   比后面的 M1A1 HC、M1A2、SEP 都强）：57.2 吨（63 短吨）、AGT1500 1500 马力、公路限速 67 公里 / 时（极速、加速同 D.m1a1）；
--   M256 120 毫米滑膛炮：M829 贫铀长杆（1985）/ M830 破甲 / M829A1（研究的第三种）、40 发；炮塔同 IPM1（贫铀装甲是 1988 年 M1A1 HA 才加的）；
--   没有 ARAT / TUSK（2006 年以后）：noEra。老的 D.m1a1（老模式、老 AI 名单、试驾靶车在用）不动
D.m1a1base = variant(D.m1a1, { like = "m1a1", noEra = true, weapons = { "gun120a1", "coax" } })
-- M1A1 HC（1988）：约 61 吨（估）、公路限速 67 公里 / 时；M256 120 毫米滑膛炮（M829A1「银弹」、M830、M829）、40 发；炮塔正面加贫铀装甲
D.m1a1hc = variant(D.m1a1, { like = "m1a1", noEra = true, speed = 52.1, accel = 5.4, weapons = { "gun120hc", "coax" } })
-- M1A2（1992）：约 62.5 吨（估）；车长独立热像仪（CITV）——猎歼式，IVIS 车际信息、定位导航；炮长镜第一代热像 3 / 10 倍；M829A1 / M830 / M830A1、42 发
D.m1a2base = variant(D.m1a2, { like = "m1a2", noEra = true, accel = 5.3, weapons = { "gun120a2", "coax" }, sightZoom = { day = { 3, 10 }, th = { 3, 10 } } })
-- M1A2 SEP（2000）：约 63 吨；第二代前视红外（炮长镜、CITV 都换了，倍率同 SEPv2）、数字地图、第三代贫铀装甲（同 SEPv2）；M829A2（M829A3 2003 年起）
D.m1a2sep = variant(D.m1a2, { like = "m1a2", noEra = true, accel = 5.2, weapons = { "gun120sep", "coax" } })
-- M1A2 SEPv3（2017）：66.8 吨（73.6 短吨）；弹药数据链（ADL）打 M829A4、车内辅助动力单元、加厚的炮塔前装甲；ARAT / TUSK / Trophy 照真车能装（改装页照 SEPv2）
D.m1a2sep3 = variant(D.m1a2, { like = "m1a2", accel = 4.9, weapons = { "gun120sep3", "coax" } })

-- 11-24 夜 C 从 Sketchfab 找的坦克（用户：「自己去 Sketchfab 找坦克加进来」「新弄的坦克不搞内饰了」——C 没有做车内，按 C 不进车里）：
--   原模型见 tools/models/blveh.json（leo2a6 / leclerc / t72b3 / t80u）、署名见 models/veh/credits.txt；尺寸、炮塔座圈、炮耳轴照转换报告（格）
-- 勒克莱尔（法国）：56.5 吨、V8X 1500 马力、72 km/h、120 毫米 CN120-26（炮塔尾舱自动装弹机，三人车组）；HL-60 炮长镜昼光 3.3 / 10 倍
D.leclerc = tracked({ cat = "tank", L = 19.3, W = 9.7, H = 7.0, hullH = 4.6, clear = 1.3, speed = 56.0, accel = 5.8, rev = 29.6, turn = 37,
  rw = { n = 6, r = 1.0, x = 3.6, z0 = -6.6, z1 = 6.6 }, era = false, skirt = true,
  turret = { pivot = V(0, 3.39, -1.89), size = V(8.7, 2.6, 12.3), style = "wedge", trav = 40, elev = { -8, 20 }, bustle = 3.5 },
  gun = { pivot = V(0, 1.76, -2.98), len = 12.0, cal = 0.44 }, coax = V(1.0, 1.7, -3.0),
  sight = V(1.5, 2.6, -2.2), cupola = V(-1.5, 2.8, 0.6),
  smoke = { banks = { { at = V(3.4, 2.0, -1.0), yaw = 35 }, { at = V(-3.4, 2.0, -1.0), yaw = -35 } }, n = 6 },
  sightZoom = { day = { 3.3, 10 }, th = { 3, 10 } },
  weapons = { "gun120", "coax" } })
-- T-72B3（俄罗斯）：46 吨、V-92S2F 1130 马力、60 km/h、125 毫米 2A46M-5（转盘式自动装弹机 22 发）；「松树-U」炮长镜昼光 4 / 12 倍、热像 3.7 / 12 倍
D.t72b3 = tracked({ cat = "tank", L = 19.9, W = 10.6, H = 6.4, hullH = 4.0, clear = 1.3, speed = 46.7, accel = 5.4, rev = 3.9, turn = 36,
  rw = { n = 6, r = 1.1, x = 3.9, z0 = -6.6, z1 = 5.6 }, era = false, skirt = true,
  turret = { pivot = V(0, 4.01, -0.09), size = V(8.0, 2.3, 8.5), style = "round", trav = 24, elev = { -6, 14 } },
  gun = { pivot = V(0, 0.85, -3.51), len = 13.85, cal = 0.45, fume = true }, coax = V(1.0, 0.9, -3.4),
  sight = V(-1.8, 2.0, -2.0), cupola = V(1.6, 2.1, 0.4),
  smoke = { banks = { { at = V(3.2, 1.3, -1.6), yaw = 40 }, { at = V(-3.2, 1.3, -1.6), yaw = -40 } }, n = 6 },
  sightZoom = { day = { 4, 12 }, th = { 3.7, 12 } },
  weapons = { "gun125r", "coax" } })
-- T-72 一族（用户 11-25「坦克单独找建模很多坦克没有建模」：科技树 T-72 乌拉尔 / A / B 原来借 T-90M，改借同族的 T-72B3 模型，性能各按自己的）
--   11-27：借来的 T-72B3 模型上的接触-5（37 格）原来三型都照样起作用——noEra 挡住（乌拉尔、A 没有爆反；B 的接触-1 按装甲算进 WtDamage.PROF）
-- T-72「乌拉尔」（1973）：41 吨、V-46 780 马力、公路 60 公里 / 时；2A26M2 125 毫米炮（游戏里按 2A46 打 3BM22 算）、TPD-2-49 合像测距 8 倍；没有爆反、没有热像
D.t72ural = variant(D.t72b3, { like = "t72b3", noEra = true, speed = 46.7, accel = 4.2, rev = 3.9, weapons = { "gun125b", "coax" }, sightZoom = { day = { 8 }, th = { 5.5 } } })
-- T-72A（1979）：41.5 吨、780 马力；2A46 炮、3BM22，TPD-K1 激光测距；炮塔正面「沙」复合装甲
D.t72a = variant(D.t72b3, { like = "t72b3", noEra = true, speed = 46.7, accel = 4.2, rev = 3.9, weapons = { "gun125b", "coax" }, sightZoom = { day = { 8 }, th = { 5.5 } } })
-- T-72B（1985）：44.5 吨、V-84 840 马力；2A46M 炮打 3BM42「芒果」、9K120 炮射导弹；接触-1 爆反（游戏里没挂爆反块，按装甲算进去）
D.t72b = variant(D.t72b3, { like = "t72b3", noEra = true, speed = 46.7, accel = 4.6, rev = 3.9, weapons = { "gun125u", "coax" }, sightZoom = { day = { 8 }, th = { 5.5 } } })

---------------------------------------------------------------- 装甲车（履带）

-- BMP-1 步兵战车（用户 11-25「需要模型自己找」：科技树 BMP-1、86 式原来借 BMP-3）：13.3 吨、UTD-20 300 马力、公路 65 公里 / 时、能浮渡；
--   单人炮塔 2A28「雷」73 毫米低压滑膛炮（PG-15V 火箭增程破甲弹、自动装弹机）+ 并列 PKT（炮塔顶的「婴儿」反坦克导弹游戏里没有）；
--   后面八名载员从车尾两扇门下车；原模型 buh-late
D.bmp1 = tracked({ cat = "apc", L = 17.7, W = 8.4, H = 5.8, hullH = 4.3, clear = 1.1, speed = 50.6, accel = 5.0, rev = 7.8, turn = 40, amphib = true, boat = true,
  rw = { n = 6, r = 0.82, x = 3.54, z0 = -4.19, z1 = 5.44 }, skirt = false,
  turret = { pivot = V(0, 4.28, 1.2), size = V(4.4, 1.5, 4.4), style = "ifv", trav = 30, elev = { -4, 33 } },
  gun = { pivot = V(0.1, 0.54, -1.72), len = 4.8, cal = 0.22 }, coax = V(0.6, 0.5, -1.9),
  sight = V(-1.0, 1.3, -0.9),
  sightZoom = { day = { 6 }, th = { 6.7 } },   -- 1PN22M1 炮长瞄准镜：昼光 6 倍、夜视 6.7 倍
  weapons = { "gun73", "malyutka", "coax" }, seats = 8 })
-- 86 式步兵战车（1986，11-27 拆开重叠的版本：原来写 base 借 BMP-1）：BMP-1 的国产型，13.3 吨、300 马力（估）、65 公里 / 时；
--   86 式 73 毫米低膛压滑膛炮（仿 2A28）+ 红箭-73 反坦克导弹（仿 9M14）+ 并列机枪；没有激光测距、主动红外夜视
D.type86 = variant(D.bmp1, { like = "bmp1", weapons = { "gun73", "hj73", "coax" } })
D.m2a3 = tracked({ cat = "apc", L = 19, W = 9.4, H = 8.4, hullH = 5.6, clear = 1.4, speed = 51.3, accel = 4.4, rev = 15.6, turn = 40,
  rw = { n = 6, r = 0.95, x = 3.7, z0 = -6.8, z1 = 6.8 }, skirt = true,
  turret = { pivot = V(0, 5.6, -0.4), size = V(5.0, 1.8, 5.2), style = "ifv", trav = 60, elev = { -9, 55 }, tow = true },
  gun = { pivot = V(0, 0.7, -2.4), len = 6.5, cal = 0.24 }, coax = V(0.9, 0.7, -2.5),
  sight = V(-1.5, 1.7, -1.8),
  sightZoom = { day = { 4, 12 }, th = { 4, 12, 24 } },   -- M2A3 炮长的综合瞄准具（IBAS）：昼光 4 / 12 倍，热像 4 / 12 倍 + 电子放大 24 倍
  smoke = { banks = { { at = V(2.4, 1.0, -2.2), yaw = 30 }, { at = V(-2.4, 1.0, -2.2), yaw = -30 } }, n = 4 },
  -- 11-27：炮照真车换成 M242 25 毫米 + M919 贫铀尾翼稳定脱壳穿甲弹（原来是 30 毫米 ac30——游戏里的旧值，布雷德利从没装过 30 毫米炮）
  weapons = { "m242m919", "tow2", "coax" }, seats = 6 })
-- 11-27 拆开重叠的版本（用户「把重叠的版本拆开」「各维度还原一致」）：科技树 M2、M2A2 原来写 base（借 M2A3：30 毫米炮、IBAS 二代热像、激光测距）
-- M2（1981；型号叫 m2a0，免得和 ImportedMeta 里表示 M2 机枪的 mg = "m2" 搞混）：22.6 吨、Cummins VTA-903T 500 马力、66 公里 / 时；
--   M242 25 毫米（M791）+ BGM-71C 改进型陶式 + 并列机枪；铝合金车体；ISU 综合瞄准具 4 / 12 倍（第一代热像，没有激光测距）
D.m2a0 = variant(D.m2a3, { like = "m2a3", speed = 51.3, accel = 4.9, weapons = { "m242", "tow1", "coax" }, sightZoom = { day = { 4, 12 }, th = { 4, 12 } } })
-- M2A2（1988）：约 30 吨（估）、VTA-903T 600 马力、61 公里 / 时（估）；加挂钢装甲（正面挡 30 毫米）、可挂爆反块；TOW-2；ISU 还是没有激光测距（ODS 改型才加）
D.m2a2 = variant(D.m2a3, { like = "m2a3", speed = 47.4, accel = 4.4, weapons = { "m242", "tow2", "coax" }, sightZoom = { day = { 4, 12 }, th = { 4, 12 } } })

---------------------------------------------------------------- 装甲车（轮式）

D.hmmwv = wheeled({ cat = "apc", L = 14, W = 6.4, H = 6.4, hullH = 4.6, clear = 1.4, speed = 81.7, accel = 15, rev = 23.3, turn = 60, light = true,
  axles = { -4.0, 4.2 }, steer = 1, wr = 1.3, ww = 0.9, wx = 2.6,
  turret = { pivot = V(0, 4.6, 0.6), size = V(2.4, 0.9, 2.4), style = "ring", trav = 90, elev = { -10, 40 } },
  gun = { pivot = V(0, 0.9, -0.6), len = 4.2, cal = 0.18 }, sight = V(0, 1.7, 0.4),
  smoke = { banks = { { at = V(1.9, 0.3, -2.4), yaw = 35, hull = true }, { at = V(-1.9, 0.3, -2.4), yaw = -35, hull = true } }, n = 2 },
  weapons = { "hmg" }, seats = 4 })
D.jltv = wheeled({ cat = "apc", L = 17, W = 7.0, H = 7.2, hullH = 5.2, clear = 1.6, speed = 77.8, accel = 14, rev = 23.3, turn = 56, light = true,
  axles = { -4.8, 4.8 }, steer = 1, wr = 1.45, ww = 1.0, wx = 2.9,
  turret = { pivot = V(0, 5.2, 0.4), size = V(2.2, 1.0, 2.2), style = "rws", trav = 80, elev = { -10, 50 } },
  gun = { pivot = V(0, 0.6, -0.6), len = 4.4, cal = 0.18 }, sight = V(0, 1.4, -0.8),
  smoke = { banks = { { at = V(1.4, 0.4, -0.6), yaw = 35 }, { at = V(-1.4, 0.4, -0.6), yaw = -35 } }, n = 2 },
  weapons = { "hmg" }, seats = 4 })
-- 87 式侦察警戒车（用户 11-27「德国目前没飞机 包括很多缺的载具全部做一下」：日本地面树「轻型 / 歼击车」一列原来空着；
--   原模型 Mikhail_Zelenov 的 Type87 ARV，tools/models/blveh.json type87rcv）：小松的 6×6 轮式侦察车（82 式指挥通信车的底盘，前两轴转向），
--   15 吨、五十铃 10PBI 柴油机 305 马力（20 马力 / 吨）、公路 100 公里 / 时；双人炮塔一门 KBA 25 毫米机关炮 + 74 式 7.62 毫米并列机枪，
--   炮塔两侧各三具烟幕弹发射筒；五人车组（车长、炮长、驾驶员、前后两名观察员，观察员能下车）。真车全长 5.99 米（含炮）、宽 2.48、高 2.8；
--   尺寸、车轴、炮塔转轴、炮耳轴、瞄准镜、烟幕弹照模型量的（ImportedMeta type87rcv）。炮塔转速、俯仰范围没查到公开数字：按同类双人炮塔估
D.type87rcv = wheeled({ cat = "apc", L = 15.2, W = 7.4, H = 7.6, hullH = 5.5, clear = 1.8, speed = 77.8, accel = 4.5, rev = 15.6, turn = 44,
  axles = { -3.85, 0.07, 4.0 }, steer = 2, wr = 1.63, ww = 1.1, wx = 2.7,
  turret = { pivot = V(0.08, 5.49, -1.54), size = V(4.9, 1.7, 4.9), style = "ifv", trav = 40, elev = { -10, 45 } },
  gun = { pivot = V(0.18, 0.62, -2.19), len = 4.9, cal = 0.16 }, coax = V(0.85, 0.86, -2.8),
  sight = V(-1.8, 1.1, -1.5),
  smoke = { banks = { { at = V(2.4, 0.4, 1.7), yaw = 50 }, { at = V(-2.4, 0.4, 1.7), yaw = -50 } }, n = 3 },
  sightZoom = { day = { 4, 8 }, th = { 4 } },
  weapons = { "ac25", "coax" }, seats = 3 })
-- BRDM-2 装甲侦察车（用户 11-27 同上：俄罗斯地面树「轻型 / 歼击车」一列原来空着、坦克也没有 1 级；原模型 zhek（Protdj），
--   tools/models/blveh.json brdm2）：1963 年起装备，7 吨、GAZ-41 汽油机 140 马力（20 马力 / 吨）、公路 95 公里 / 时，能浮渡（水上喷水推进 10 公里 / 时）；
--   车腹两边各两个辅助小轮（越壕时放下，游戏里收着）；BPU-1 单人锥形炮塔：KPVT 14.5 毫米重机枪 + PKT 7.62 毫米并列机枪，手摇转塔、俯仰 −5°～+30°；
--   装甲首上 14 毫米、侧面 7 毫米。四人车组（车长、驾驶员、炮手、观察员）。尺寸、车轴、炮塔转轴、机枪耳轴照模型量的（ImportedMeta brdm2）
D.brdm2 = wheeled({ cat = "apc", L = 15.5, W = 6.6, H = 6.6, hullH = 5.7, clear = 1.2, speed = 73.9, accel = 4.4, rev = 15.6, turn = 46, amphib = true, boat = true,
  axles = { -3.27, 4.73 }, steer = 1, wr = 1.55, ww = 1.0, wx = 2.42,
  turret = { pivot = V(0.01, 5.58, 0.73), size = V(3.6, 1.0, 3.6), style = "ifv", trav = 24, elev = { -5, 30 } },
  gun = { pivot = V(-0.01, 0.39, -0.85), len = 3.4, cal = 0.1 },
  sight = V(-0.45, 0.75, -0.9),
  sightZoom = { day = { 2.6 } },   -- PP-61AM 潜望瞄准镜 2.6 倍，没有夜视
  weapons = { "kpvt", "coax" }, seats = 2 })

---------------------------------------------------------------- 防空

D.pgz07 = tracked({ cat = "aa", L = 22, W = 9.6, H = 9.6, hullH = 4.4, clear = 1.3, speed = 46.7, accel = 5.0, rev = 11.7, turn = 36,
  rw = { n = 6, r = 1.05, x = 3.8, z0 = -7.4, z1 = 7.2 }, skirt = true,
  turret = { pivot = V(0, 4.4, 0.8), size = V(5.6, 2.6, 6.2), style = "spaag", trav = 90, elev = { -5, 85 }, radar = true, twin = 3.4 },
  gun = { pivot = V(0, 1.3, -1.4), len = 9.5, cal = 0.24 }, sight = V(0, 2.2, -2.6),
  smoke = { banks = { { at = V(2.7, 0.8, -2.8), yaw = 35 }, { at = V(-2.7, 0.8, -2.8), yaw = -35 } }, n = 4 },
  weapons = { "ac35" } })
D.m163 = tracked({ cat = "aa", L = 15, W = 8.2, H = 8.0, hullH = 5.4, clear = 1.2, speed = 52.1, accel = 4.6, rev = 15.6, turn = 42,
  rw = { n = 5, r = 0.95, x = 3.4, z0 = -5.6, z1 = 5.6 },
  turret = { pivot = V(0, 5.4, 1.4), size = V(3.4, 1.4, 3.4), style = "vulcan", trav = 80, elev = { -5, 80 } },
  gun = { pivot = V(0, 0.9, -1.0), len = 5.4, cal = 0.3, gatling = true }, sight = V(-1.0, 1.8, -0.4),
  smoke = { banks = { { at = V(3.2, -1.4, -6.4), yaw = 30, hull = true }, { at = V(-3.2, -1.4, -6.4), yaw = -30, hull = true } }, n = 4 },
  weapons = { "vulcan" } })
D.pgl625 = wheeled({ cat = "aa", L = 24, W = 8.4, H = 9.6, hullH = 5.6, clear = 1.8, speed = 66.1, accel = 9, rev = 19.4, turn = 40, truck = true,
  axles = { -7.6, -3.8, 5.6 }, steer = 1, wr = 1.55, ww = 1.1, wx = 3.4,
  turret = { pivot = V(0, 5.6, 2.4), size = V(4.6, 2.2, 4.6), style = "spaag", trav = 90, elev = { -5, 85 }, radar = true, twin = 2.8 },
  gun = { pivot = V(0, 1.1, -1.2), len = 7.4, cal = 0.22 }, sight = V(0, 2.0, -2.0),
  smoke = { banks = { { at = V(2.3, 0.6, -2.4), yaw = 35 }, { at = V(-2.3, 0.6, -2.4), yaw = -35 } }, n = 4 },
  weapons = { "ac35" } })
-- 铠甲-S1（用户 11-24 找的俄系；SanderWolf_ 的原模型 pantsir）：KamAZ-6560 8×8 底盘、后部战斗模块——两门 2A38M 双管 30 炮 + 12 枚 57E6 地空导弹，
--   顶上搜索雷达一直转、前面跟踪雷达；尺寸按原模型（全长约 10.3 米）
D.pantsir = wheeled({ cat = "aa", L = 28.8, W = 8.4, H = 11.4, hullH = 7.5, clear = 1.9, speed = 70.0, accel = 8, rev = 19.4, turn = 34, truck = true,
  axles = { -10.6, -4.9, 5.9, 9.8 }, steer = 2, wr = 1.88, ww = 1.06, wx = 2.75,
  turret = { pivot = V(0, 7.64, 5.95), size = V(4.6, 2.4, 11.0), style = "spaag", trav = 90, elev = { -5, 82 }, twin = 4.1 },
  gun = { pivot = V(0, 1.33, 0.53), len = 7.2, cal = 0.2 }, sight = V(0, 3.1, -2.6),
  smoke = { banks = { { at = V(2.4, 0.4, -1.6), yaw = 35 }, { at = V(-2.4, 0.4, -1.6), yaw = -35 } }, n = 4 },
  weapons = { "ac30aa", "s57e6" } })
-- 9K31「箭-1」防空车（9P31 发射车；用户 11-27「很多缺的载具全部做一下」：俄罗斯地面树「自行防空」一列只有六级的铠甲；
--   原模型 xFORTUNAx（车体是 zhek 的 BRDM-2），tools/models/blveh.json strela1）：1968 年起装备，BRDM-2 底盘（7 吨、140 马力、95 公里 / 时、能浮渡），
--   炮塔换成转台 + 俯仰的四联装 9M31 发射架（光学瞄准，红外导引头）；三人车组。转轴、俯仰轴照原模型的空节点（ImportedMeta strela1）
D.strela1 = wheeled({ cat = "aa", L = 16.1, W = 6.9, H = 9.5, hullH = 5.6, clear = 1.2, speed = 73.9, accel = 4.2, rev = 15.6, turn = 46, amphib = true, boat = true,
  axles = { -3.39, 4.91 }, steer = 1, wr = 1.6, ww = 1.0, wx = 2.52,
  turret = { pivot = V(0, 5.55, 0.86), size = V(3.7, 1.8, 3.7), style = "launcher", trav = 40, elev = { -5, 80 } },
  gun = { pivot = V(0, 2.91, 0), len = 3.0, cal = 0 }, sight = V(0, 2.4, -1.4),
  weapons = { "s9m31" } })
D.ld2000 = wheeled({ cat = "aa", L = 30, W = 8.6, H = 10.4, hullH = 5.8, clear = 1.9, speed = 66.1, accel = 8, rev = 19.4, turn = 34, truck = true,
  axles = { -10.6, -6.6, 3.4, 7.2 }, steer = 2, wr = 1.65, ww = 1.15, wx = 3.5,
  turret = { pivot = V(0, 5.8, 4.6), size = V(4.0, 2.6, 4.0), style = "vulcan", trav = 90, elev = { -5, 85 }, radar = true },
  gun = { pivot = V(0, 1.3, -1.2), len = 6.0, cal = 0.36, gatling = true }, sight = V(-1.2, 2.2, -1.0),
  smoke = { banks = { { at = V(3.6, -1.6, -11.4), yaw = 30, hull = true }, { at = V(-3.6, -1.6, -11.4), yaw = -30, hull = true } }, n = 4 },
  weapons = { "vulcan" } })
D.mshorad = wheeled({ cat = "aa", L = 22, W = 8.4, H = 9.0, hullH = 5.8, clear = 1.6, speed = 75.4, accel = 10, rev = 23.3, turn = 44,
  axles = { -6.8, -3.2, 2.6, 6.2 }, steer = 2, wr = 1.45, ww = 1.0, wx = 3.5,
  turret = { pivot = V(0, 5.8, 0.6), size = V(4.0, 1.8, 4.2), style = "ifv", trav = 80, elev = { -8, 70 }, pods = true },
  gun = { pivot = V(0, 0.7, -2.0), len = 6.4, cal = 0.22 }, sight = V(-1.3, 1.6, -1.6),
  smoke = { banks = { { at = V(3.6, -0.2, -6.0), yaw = 30, hull = true }, { at = V(-3.6, -0.2, -6.0), yaw = -30, hull = true } }, n = 4 },
  weapons = { "ac30" } })
D.cram = wheeled({ cat = "aa", L = 19, W = 8.0, H = 9.6, hullH = 4.4, clear = 1.6, speed = 46.7, accel = 6, rev = 15.6, turn = 30, truck = true,
  axles = { -5.4, -2.0, 5.4 }, steer = 1, wr = 1.5, ww = 1.0, wx = 3.2,
  turret = { pivot = V(0, 4.4, 3.0), size = V(3.6, 2.4, 3.6), style = "vulcan", trav = 100, elev = { -5, 85 }, dome = true },
  gun = { pivot = V(0, 1.2, -1.2), len = 6.0, cal = 0.3, gatling = true }, sight = V(-1.0, 2.0, -0.6),
  smoke = { banks = { { at = V(3.4, -0.8, -7.4), yaw = 30, hull = true }, { at = V(-3.4, -0.8, -7.4), yaw = -30, hull = true } }, n = 2 },
  weapons = { "vulcan" } })

---------------------------------------------------------------- 火炮

D.plz07 = tracked({ cat = "arty", L = 22, W = 9.6, H = 9.0, hullH = 4.4, clear = 1.3, speed = 46.7, accel = 4.2, rev = 11.7, turn = 34,
  rw = { n = 6, r = 1.0, x = 3.8, z0 = -7.4, z1 = 7.2 },
  turret = { pivot = V(0, 4.4, 2.2), size = V(7.2, 3.0, 8.4), style = "sph", trav = 25, elev = { -3, 65 } },
  gun = { pivot = V(0, 1.4, -4.0), len = 15, cal = 0.42, brake = true, fume = true }, sight = V(-2.4, 2.8, -3.0),
  smoke = { banks = { { at = V(3.4, 1.4, -3.4), yaw = 35 }, { at = V(-3.4, 1.4, -3.4), yaw = -35 } }, n = 4 },
  weapons = { "how155" } })
D.m109a7 = tracked({ cat = "arty", L = 24, W = 10.2, H = 9.4, hullH = 4.2, clear = 1.4, speed = 47.4, accel = 4.0, rev = 14.0, turn = 32,
  rw = { n = 7, r = 1.0, x = 4.0, z0 = -7.8, z1 = 7.6 },
  turret = { pivot = V(0, 4.2, 2.8), size = V(8.4, 3.4, 10.4), style = "sph", trav = 22, elev = { -3, 70 } },
  gun = { pivot = V(0, 1.6, -5.0), len = 17, cal = 0.44, brake = true, fume = true }, sight = V(-2.8, 3.0, -3.6),
  smoke = { banks = { { at = V(4.0, 1.6, -4.4), yaw = 35 }, { at = V(-4.0, 1.6, -4.4), yaw = -35 } }, n = 4 },
  weapons = { "how155" } })
D.m270 = tracked({ cat = "arty", L = 20, W = 9.4, H = 8.2, hullH = 4.4, clear = 1.4, speed = 49.8, accel = 4.0, rev = 14.0, turn = 34,
  rw = { n = 6, r = 1.0, x = 3.7, z0 = -6.8, z1 = 6.8 }, cab = true,
  turret = { pivot = V(0, 4.4, 2.6), size = V(5.8, 2.6, 9.0), style = "launcher", trav = 30, elev = { 0, 60 } },
  gun = { pivot = V(0, 0.4, 0), len = 0, cal = 0 }, sight = V(0, -0.6, -8.6),
  smoke = { banks = { { at = V(3.4, -1.4, -8.6), yaw = 30, hull = true }, { at = V(-3.4, -1.4, -8.6), yaw = -30, hull = true } }, n = 4 },
  weapons = { "mlrs" } })

-- 爱国者（只打飞机；在有飞机之前不给选）
D.patriot = wheeled({ cat = "aa", L = 28, W = 8.4, H = 10, hullH = 4.4, clear = 1.8, speed = 54.4, accel = 6, rev = 15.6, turn = 32, truck = true, needsAir = true,
  axles = { -9.6, -5.8, 6.2, 9.6 }, steer = 1, wr = 1.6, ww = 1.1, wx = 3.4,
  turret = { pivot = V(0, 4.4, 3.0), size = V(6.0, 3.0, 11), style = "launcher", trav = 30, elev = { 0, 38 } },
  gun = { pivot = V(0, 0.4, 0), len = 0, cal = 0 }, sight = V(0, -0.4, -12),
  smoke = { banks = { { at = V(3.4, -0.4, -13), yaw = 30, hull = true }, { at = V(-3.4, -0.4, -13), yaw = -30, hull = true } }, n = 2 },
  weapons = {} })

-- 没有激光测距机的（用户 11-25「全部都做」⑤：战雷历史模式里这种车按 R 是车长估距——要等两秒、有误差）：
--   豹 1（体视测距仪，豹 1A5 才换激光）、M60A1（合像测距仪，M60A3 才有激光）、BMP-1；其余的车都有激光测距
local NO_LRF = { leo1 = true, m60a1 = true, bmp1 = true, t64a = true,   -- T-64A：TPD-2-49 合像测距瞄准镜（T-64B 才有激光）
  brdm2 = true, strela1 = true, type87rcv = true,   -- 11-27 补的：BRDM-2 的 PP-61AM、箭-1 的光学瞄准具、87 式的潜望瞄准镜都没有激光测距
  m60 = true, m60a1rise = true, leo1a1a1 = true,   -- 11-27 拆出来的：M60 / M60A1 RISE 合像测距仪、豹 1A1A1 体视测距仪
  type86 = true, m2a0 = true, m2a2 = true }   -- 86 式（同 BMP-1）、M2 / M2A2 的 ISU 都没有激光测距
-- 每个型号补上默认值、名字
for id, d in pairs(D) do
  d.id = id
  d.lrf = not NO_LRF[id]
  d.seats = d.seats or 1
  d.travel = d.travel or ((d.arch == "wheeled") and 0.75 or 0.55)   -- 悬架行程（上下各多少格）
  d.rev = d.rev or d.speed * 0.4
  if d.arch == "tracked" then d.rw.y = d.rw.y or d.rw.r end
end

-- 有原模型的型号（ImportedMeta：网页版装备模型原样转的，真实尺寸）：炮塔转轴、炮耳轴、炮口位置照原模型——
--   炮弹从看得见的炮口出去、炮长瞄准镜跟着真炮塔；不管导没导入都一样（服务器和客户端算出来一致）
do
  local ok, IM = pcall(function()
    local m = script and script.Parent and script.Parent:FindFirstChild("ImportedMeta")
    return m and require(m) or nil
  end)
  if ok and type(IM) == "table" and IM.alias and IM.m then
    for id, key in pairs(IM.alias) do
      local d, info = D[id], IM.m[key]
      if d and info and (info.tur or info.gun) then
        -- 型号表原来的转轴、炮长留着：没导入原模型时零件拼的炮塔、炮还按它摆（不然炮塔离开车体顶，C-RAM、斯特赖克高出 2 格）
        d.turret.pivot0 = d.turret.pivot
        if d.gun then d.gun.pivot0, d.gun.len0 = d.gun.pivot, d.gun.len end
        -- 原模型没有单独的炮塔（爱国者只有会俯仰的发射架）：转轴照型号表，耳轴照原模型（客户端 VehModels 也是这么摆的）
        local tur = info.tur and V(info.tur[1], info.tur[2], info.tur[3]) or d.turret.pivot
        d.turret.pivot = tur   -- 瞄准镜、烟幕弹发射架都是相对炮塔转轴的，跟着挪
        if info.gun then
          d.gun.pivot = V(info.gun[1], info.gun[2], info.gun[3]) - tur
          if info.muz and info.muz > 1 then d.gun.len = info.muz end
        end
        -- 炮长主瞄准镜、并列机枪口照原模型（用户：观瞄系统位置要对）：瞄准镜视角从模型上那个镜头看出去
        if info.sight then d.sight = V(info.sight[1], info.sight[2], info.sight[3]) - tur end
        if info.coax then d.coax = V(info.coax[1], info.coax[2], info.coax[3]) - tur end
        -- 遥控武器站（M1A2 车长位的 CROWS + M2）：底座跟着炮塔转、自己再转，M2 自己俯仰；机枪那一栏从并列机枪换成它的 12.7 毫米机枪
        --   （用户：机枪也要能转动、开火位置和枪口对上、弹道顺着枪管）
        if info.rws and info.rws.p and info.rws.g then
          local rp = V(info.rws.p[1], info.rws.p[2], info.rws.p[3])
          local rg = V(info.rws.g[1], info.rws.g[2], info.rws.g[3])
          d.rws = { pivot = rp - tur, gun = rg - rp, len = info.rws.muz or 2.5, trav = 120, rate = 90, elev = { -20, 60 }, mk = info.rws.mk }
          if info.rws.mk == "manual" then   -- 手动的车长重机枪（99A 的 12.7 毫米，真车上还有一挺 7.62 并列机枪）：并列机枪留着，第 3 栏是车顶重机枪
            table.insert(d.weapons, "hmg")
          else
            for i, wid in ipairs(d.weapons) do
              if wid == "coax" then d.weapons[i] = "hmg" end
            end
          end
        end
        d.model = key
      end
    end
  end
end

-- 零件拼的坦克（没有原模型：M10）：车长位上一个会转的遥控武器站（用户 11-19：坦克的机枪要能转，开火位置要在机枪）——
--   机枪那一栏从并列机枪（主炮旁边）换成它的 12.7 毫米机枪；有原模型的坦克在元数据里给（tools/models/vehrws.py）
for _, d in pairs(D) do
  if d.cat == "tank" and not d.rws and not d.model and d.cupola and not d.noRoofMg then
    local top = (d.turret and d.turret.size and d.turret.size.Y) or 2.3
    d.rws = { pivot = V(d.cupola.X, top, d.cupola.Z), gun = V(0, 0.62, -0.45), len = 2.45, trav = 120, rate = 90, elev = { -15, 55 }, mk = "rws" }
    for i, wid in ipairs(d.weapons) do
      if wid == "coax" then d.weapons[i] = "hmg" end
    end
  end
end

-- 用户 11-22：「坦克不要弄哪个机枪」——主战坦克（cat = "tank"）不要机枪：并列机枪、车顶的遥控武器站 / 手动重机枪都去掉，只剩主炮
--   （机器人开的坦克打步兵也用主炮）；步战车、轻型车、防空车照旧。想加回来把 VehDefs.TANK_MG 改成 true
VehDefs.TANK_MG = false
if not VehDefs.TANK_MG then
  for _, d in pairs(D) do
    if d.cat == "tank" then
      d.rws, d.noRoofMg = nil, true
      local keep = {}
      for _, wid in ipairs(d.weapons or {}) do
        if wid ~= "coax" and wid ~= "hmg" then table.insert(keep, wid) end
      end
      d.weapons = keep
    end
  end
end

function VehDefs.get(id) return D[id] end

-- 炮塔、炮的坐标系：base 是车底（着地中心）的 CFrame
function VehDefs.turretCF(d, base, yaw)
  return base * CFrame.new(d.turret.pivot) * CFrame.Angles(0, -math.rad(yaw or 0), 0)
end
function VehDefs.gunCF(d, base, yaw, pitch)
  return VehDefs.turretCF(d, base, yaw) * CFrame.new(d.gun.pivot) * CFrame.Angles(math.rad(pitch or 0), 0, 0)
end
-- 遥控武器站：底座跟炮塔转（yaw）再自己转（my，度，往右为正，同炮塔），M2 俯仰（mp，度，抬头为正）
function VehDefs.rwsCF(d, base, yaw, my, mp)
  local R = d.rws
  return VehDefs.turretCF(d, base, yaw) * CFrame.new(R.pivot) * CFrame.Angles(0, -math.rad(my or 0), 0) * CFrame.new(R.gun)
    * CFrame.Angles(math.rad(mp or 0), 0, 0)
end
-- 遥控武器站要转到多少才对着 target（世界坐标）：返回 my、mp（夹在俯仰范围里）
function VehDefs.rwsAim(d, base, yaw, target)
  local R = d.rws
  local piv = VehDefs.turretCF(d, base, yaw) * CFrame.new(R.pivot)
  local rel = piv:PointToObjectSpace(target)
  local my = math.deg(math.atan2(rel.X, -rel.Z))
  local horiz = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
  local mp = math.deg(math.atan2(rel.Y - R.gun.Y, math.max(horiz, 1)))
  return my, math.clamp(mp, R.elev[1], R.elev[2])
end
-- 炮口（主炮）；coax 并列机枪口；rws 遥控武器站的枪口（my、mp 是它的转角）
function VehDefs.muzzle(d, base, yaw, pitch, which, my, mp)
  if which == "rws" and d.rws then
    return VehDefs.rwsCF(d, base, yaw, my, mp) * CFrame.new(0, 0, -d.rws.len)
  end
  if which == "coax" and d.coax then
    local t = VehDefs.turretCF(d, base, yaw) * CFrame.new(d.coax) * CFrame.Angles(math.rad(pitch or 0), 0, 0)
    return t * CFrame.new(0, 0, -1.2)
  end
  return VehDefs.gunCF(d, base, yaw, pitch) * CFrame.new(0, 0, -(d.gun.len > 0 and d.gun.len or 2))
end
-- 这件武器从哪个口出去：遥控站的 12.7 毫米机枪 → rws；别的机枪 → 并列机枪口；主炮 → nil
function VehDefs.mgWhich(d, wid)
  local w = VehDefs.W[wid]
  if not w or w.kind ~= "gun" then return nil end
  if wid == "hmg" and d.rws then return "rws" end
  return d.coax and "coax" or nil
end
-- 烟幕弹发射筒：返回 { { pos, dir }, … }（世界坐标）；装在炮塔上的随炮塔转，hull 的装在车体上
function VehDefs.smokeTubes(d, base, yaw)
  local out = {}
  local S = d.smoke
  if not S then return out end
  local tcf = VehDefs.turretCF(d, base, yaw)
  for _, b in ipairs(S.banks) do
    local frame = (b.hull and (base * CFrame.new(0, d.hullH, 0)) or tcf) * CFrame.new(b.at)
    for i = 1, S.n do
      local fan = (S.n > 1) and ((i - 1) / (S.n - 1) - 0.5) or 0
      local yaw2 = math.rad(b.yaw + fan * 40 * (b.yaw >= 0 and 1 or -1))
      local local_ = CFrame.Angles(0, -yaw2, 0) * CFrame.Angles(math.rad(35), 0, 0)
      local cf = frame * CFrame.new(fan * 0.9, (i % 2) * 0.35, 0) * local_
      table.insert(out, { pos = cf.Position, dir = cf.LookVector })
    end
  end
  return out
end

return VehDefs
