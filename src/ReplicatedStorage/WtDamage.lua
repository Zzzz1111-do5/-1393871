-- Roblox全面大战场——战雷式的车辆伤害模型（服务器、客户端共用：服务器算伤害，客户端画 X 光命中回放、准星的穿深指示）
--   用户 11-24：「把整个游戏做成战雷」，问了范围以后四项全勾（坦克平显、乘员和模块伤害 + X 光回放、对局玩法、飞机）：
--   · 装甲按毫米（动能弹 ke / 化学能 ce 两个数），分车体 / 炮塔、正面 / 侧面 / 后面 / 顶上；首下、炮塔座圈、炮盾是弱点
--   · 弹按穿深（毫米，脱壳穿甲弹随距离掉一点），入射角越斜等效越厚、太斜会跳弹（破甲弹太斜引信不发火）
--   · 击穿以后弹芯 / 金属射流顺着弹道往里钻、一锥破片散开：打到哪个乘员、哪个模块就伤哪个——
--     乘员（驾驶员、炮长、车长、装填手）各自有血，模块（发动机、传动、履带、炮管、炮闩、炮塔驱动、弹药架、油箱）各自有血；
--     乘员剩不到一半、或者弹药架殉爆，车就算被击毁（照战雷：四人车组剩一个、三人车组剩一个就完了）
--   坐标：车的「底座」系（同 VehDefs：底面中心、y 朝上、−z 朝前，格）；炮塔上的零件在炮塔系（转轴处、跟炮塔转）
local W = {}
local V = Vector3.new
local M = 2.8   -- 1 米 = 2.8 格

---------------------------------------------------------------- 装甲（毫米）：{ ke 动能弹, ce 破甲弹 }

-- hull / tur：f 正面、s 侧面、r 后面、t 顶上（炮塔侧面前半截按 sf，后半截按 s）；crew 车组（角色顺序：驾驶员 drv、炮长 gnr、车长 cmd、装填手 ldr）；
--   lay 布局：w4 西方四人坦克（弹在炮塔尾舱、有泄压板）、e3 东方三人坦克（转盘式自动装弹机在车体底、没有泄压）、ifv 步战车（发动机在前）、
--   ifvr 步战车（发动机在后：BMP-3）、apc 轮式装甲车、light 轻型车、spg 自行火炮 / 防空（炮塔大、弹在炮塔里）
W.PROF = {
  m1a2 = { lay = "w4", hull = { f = { 560, 850 }, s = { 70, 90 }, r = { 30, 30 }, t = { 30, 30 } },
    tur = { f = { 800, 1300 }, sf = { 300, 350 }, s = { 100, 120 }, r = { 60, 60 }, t = { 45, 45 } }, blowout = true },
  m1a1 = { lay = "w4", hull = { f = { 520, 750 }, s = { 65, 80 }, r = { 30, 30 }, t = { 30, 30 } },
    tur = { f = { 650, 1100 }, sf = { 260, 300 }, s = { 90, 110 }, r = { 60, 60 }, t = { 40, 40 } }, blowout = true },
  -- 11-27 拆开重叠的版本：M1 一族各自的装甲（估：同一个比例尺，按公开资料的代次——M1 第一代伯灵顿复合装甲、IPM1 炮塔正面加厚、
  --   M1A1 HA / HC 炮塔正面加贫铀、M1A2 第二代贫铀、SEP / SEPv2 第三代贫铀、SEPv3 炮塔前装甲再加厚）；弹都在炮塔尾舱、有泄压板
  m1 = { lay = "w4", hull = { f = { 350, 600 }, s = { 60, 75 }, r = { 30, 30 }, t = { 30, 30 } },
    tur = { f = { 380, 700 }, sf = { 200, 260 }, s = { 90, 110 }, r = { 60, 60 }, t = { 40, 40 } }, blowout = true },
  m1ip = { lay = "w4", hull = { f = { 380, 650 }, s = { 60, 75 }, r = { 30, 30 }, t = { 30, 30 } },
    tur = { f = { 450, 800 }, sf = { 230, 280 }, s = { 90, 110 }, r = { 60, 60 }, t = { 40, 40 } }, blowout = true },
  -- 科技树的 M1A1（1985，11-27 审查第 1 条）：炮塔、车体同 IPM1（战雷的开发日志也写 M1A1 用的是 IPM1 的炮塔；贫铀装甲是 1988 年 M1A1 HA 才加的，估）；
  --   老的 m1a1（上面那行 650 / 1100，老模式在用）不动
  m1a1base = { lay = "w4", hull = { f = { 380, 650 }, s = { 60, 75 }, r = { 30, 30 }, t = { 30, 30 } },
    tur = { f = { 450, 800 }, sf = { 230, 280 }, s = { 90, 110 }, r = { 60, 60 }, t = { 40, 40 } }, blowout = true },
  m1a1hc = { lay = "w4", hull = { f = { 540, 800 }, s = { 65, 80 }, r = { 30, 30 }, t = { 30, 30 } },
    tur = { f = { 720, 1200 }, sf = { 280, 320 }, s = { 95, 115 }, r = { 60, 60 }, t = { 40, 40 } }, blowout = true },
  m1a2base = { lay = "w4", hull = { f = { 560, 850 }, s = { 70, 90 }, r = { 30, 30 }, t = { 30, 30 } },
    tur = { f = { 760, 1250 }, sf = { 300, 350 }, s = { 100, 120 }, r = { 60, 60 }, t = { 45, 45 } }, blowout = true },
  m1a2sep = { lay = "w4", hull = { f = { 560, 850 }, s = { 70, 90 }, r = { 30, 30 }, t = { 30, 30 } },          -- 装甲同 SEPv2（第三代贫铀是 SEP 换的）
    tur = { f = { 800, 1300 }, sf = { 300, 350 }, s = { 100, 120 }, r = { 60, 60 }, t = { 45, 45 } }, blowout = true },
  m1a2sep3 = { lay = "w4", hull = { f = { 620, 950 }, s = { 70, 90 }, r = { 30, 30 }, t = { 30, 30 } },
    tur = { f = { 860, 1400 }, sf = { 330, 400 }, s = { 100, 120 }, r = { 60, 60 }, t = { 45, 45 } }, blowout = true },
  leclerc = { lay = "e3", hull = { f = { 520, 750 }, s = { 70, 90 }, r = { 30, 30 }, t = { 30, 30 } },
    tur = { f = { 800, 1250 }, sf = { 300, 380 }, s = { 100, 130 }, r = { 50, 50 }, t = { 40, 40 } }, blowout = true },
  t72b3 = { lay = "e3", hull = { f = { 520, 900 }, s = { 80, 140 }, r = { 40, 40 }, t = { 35, 35 } },
    tur = { f = { 650, 1150 }, sf = { 280, 400 }, s = { 120, 200 }, r = { 55, 55 }, t = { 40, 50 } } },
  -- T-72 一族（用户 11-25：改借 T-72B3 模型，装甲按各自的年代）
  t72ural = { lay = "e3", hull = { f = { 335, 450 }, s = { 80, 80 }, r = { 40, 40 }, t = { 30, 30 } },       -- 首上 80 毫米钢 + 玻璃钢夹层
    tur = { f = { 380, 450 }, sf = { 250, 280 }, s = { 100, 110 }, r = { 55, 55 }, t = { 40, 40 } } },
  t72a = { lay = "e3", hull = { f = { 360, 490 }, s = { 80, 80 }, r = { 40, 40 }, t = { 30, 30 } },          -- 炮塔正面「沙」复合装甲
    tur = { f = { 410, 500 }, sf = { 260, 300 }, s = { 100, 110 }, r = { 55, 55 }, t = { 40, 40 } } },
  t72b = { lay = "e3", hull = { f = { 480, 850 }, s = { 80, 130 }, r = { 40, 40 }, t = { 30, 35 } },         -- 接触-1 爆反算进去
    tur = { f = { 520, 950 }, sf = { 270, 380 }, s = { 110, 180 }, r = { 55, 55 }, t = { 40, 45 } } },
  t90m = { lay = "e3", hull = { f = { 600, 1000 }, s = { 80, 150 }, r = { 40, 40 }, t = { 40, 40 } },
    tur = { f = { 750, 1300 }, sf = { 300, 450 }, s = { 150, 250 }, r = { 60, 60 }, t = { 45, 60 } } },
  ztz99a = { lay = "e3", hull = { f = { 650, 1000 }, s = { 90, 150 }, r = { 40, 40 }, t = { 40, 40 } },
    tur = { f = { 800, 1350 }, sf = { 320, 450 }, s = { 120, 180 }, r = { 60, 60 }, t = { 45, 50 } } },
  ztz96 = { lay = "e3", hull = { f = { 480, 650 }, s = { 80, 100 }, r = { 40, 40 }, t = { 35, 35 } },
    tur = { f = { 520, 750 }, sf = { 250, 300 }, s = { 100, 130 }, r = { 50, 50 }, t = { 40, 40 } } },
  -- 11-27 拆开重叠的版本（估）：96 式（1997，没有爆反、复合装甲比 96B 薄）、96A（同 96B 的车体炮塔，FY-4 爆反另算：TankMods）、
  --   99 式（2001，炮塔正面楔形附加装甲，比 99A 薄）、T-90A（焊接炮塔；接触-5 另算）
  ztz96base = { lay = "e3", hull = { f = { 400, 520 }, s = { 80, 100 }, r = { 40, 40 }, t = { 35, 35 } },
    tur = { f = { 450, 620 }, sf = { 220, 260 }, s = { 100, 130 }, r = { 50, 50 }, t = { 40, 40 } } },
  ztz96a = { lay = "e3", hull = { f = { 480, 650 }, s = { 80, 100 }, r = { 40, 40 }, t = { 35, 35 } },
    tur = { f = { 520, 750 }, sf = { 250, 300 }, s = { 100, 130 }, r = { 50, 50 }, t = { 40, 40 } } },
  ztz99base = { lay = "e3", hull = { f = { 600, 900 }, s = { 90, 150 }, r = { 40, 40 }, t = { 40, 40 } },
    tur = { f = { 700, 1150 }, sf = { 300, 420 }, s = { 120, 180 }, r = { 60, 60 }, t = { 45, 50 } } },
  t90a = { lay = "e3", hull = { f = { 550, 900 }, s = { 80, 140 }, r = { 40, 40 }, t = { 35, 40 } },
    tur = { f = { 650, 1150 }, sf = { 280, 420 }, s = { 130, 220 }, r = { 60, 60 }, t = { 45, 55 } } },
  -- 科技树换真模型的几型（用户 11-25）：视线方向的等效厚度（毫米，动能 / 化学能），按公开资料估
  t80u = { lay = "e3", hull = { f = { 540, 850 }, s = { 80, 150 }, r = { 40, 40 }, t = { 30, 40 } },          -- 首上复合装甲 + 接触-5
    tur = { f = { 650, 1150 }, sf = { 280, 420 }, s = { 120, 200 }, r = { 60, 60 }, t = { 40, 50 } } },
  t80b = { lay = "e3", hull = { f = { 420, 480 }, s = { 80, 80 }, r = { 40, 40 }, t = { 30, 30 } },          -- 没有爆反
    tur = { f = { 450, 500 }, sf = { 250, 280 }, s = { 100, 110 }, r = { 60, 60 }, t = { 40, 40 } } },
  t80bvm = { lay = "e3", hull = { f = { 600, 1000 }, s = { 80, 150 }, r = { 40, 40 }, t = { 30, 40 } },      -- 化石重型爆反
    tur = { f = { 700, 1250 }, sf = { 300, 450 }, s = { 140, 240 }, r = { 60, 60 }, t = { 40, 55 } } },
  t64a = { lay = "e3", hull = { f = { 330, 410 }, s = { 80, 80 }, r = { 40, 40 }, t = { 30, 30 } },          -- 首上钢 + 玻璃钢复合（K 型）；没有爆反
    tur = { f = { 400, 450 }, sf = { 230, 260 }, s = { 100, 110 }, r = { 60, 60 }, t = { 40, 40 } } },        -- 铸钢炮塔里夹铝
  t64b = { lay = "e3", hull = { f = { 380, 450 }, s = { 80, 80 }, r = { 40, 40 }, t = { 30, 30 } },
    tur = { f = { 430, 500 }, sf = { 240, 280 }, s = { 100, 110 }, r = { 60, 60 }, t = { 40, 40 } } },
  type74 = { lay = "w4", hull = { f = { 160, 160 }, s = { 35, 35 }, r = { 25, 25 }, t = { 20, 20 } },        -- 首上 80 毫米斜 65°；铸造炮塔
    tur = { f = { 195, 195 }, sf = { 120, 120 }, s = { 75, 75 }, r = { 50, 50 }, t = { 30, 30 } } },
  type74g = { lay = "w4", hull = { f = { 160, 160 }, s = { 45, 45 }, r = { 25, 25 }, t = { 20, 20 } },       -- 侧裙板
    tur = { f = { 195, 195 }, sf = { 120, 120 }, s = { 75, 75 }, r = { 50, 50 }, t = { 30, 30 } } },
  leo2a6 = { lay = "w4", hull = { f = { 560, 850 }, s = { 70, 90 }, r = { 30, 30 }, t = { 30, 30 } },        -- 炮塔楔形附加装甲；炮塔尾舱的弹有泄压板
    tur = { f = { 820, 1300 }, sf = { 300, 350 }, s = { 100, 120 }, r = { 60, 60 }, t = { 45, 45 } }, blowout = true },
  leo2a4 = { lay = "w4", hull = { f = { 450, 620 }, s = { 70, 90 }, r = { 30, 30 }, t = { 30, 30 } },
    tur = { f = { 600, 950 }, sf = { 260, 300 }, s = { 90, 110 }, r = { 60, 60 }, t = { 40, 40 } }, blowout = true },
  leo2a7v = { lay = "w4", hull = { f = { 620, 900 }, s = { 90, 160 }, r = { 30, 30 }, t = { 40, 40 } },      -- 新一代模块装甲、车体两侧加挂
    tur = { f = { 900, 1400 }, sf = { 330, 420 }, s = { 120, 180 }, r = { 60, 60 }, t = { 50, 60 } }, blowout = true },
  type10 = { lay = "e3", hull = { f = { 500, 750 }, s = { 70, 120 }, r = { 30, 30 }, t = { 30, 30 } },        -- 模块化复合装甲；尾舱自动装弹机有泄压板
    tur = { f = { 650, 1000 }, sf = { 280, 360 }, s = { 100, 150 }, r = { 50, 50 }, t = { 40, 40 } }, blowout = true },
  m551 = { lay = "w4", hull = { f = { 45, 45 }, s = { 25, 25 }, r = { 20, 20 }, t = { 15, 15 } },             -- 铝合金车体，机枪弹打得穿
    tur = { f = { 60, 60 }, sf = { 35, 35 }, s = { 25, 25 }, r = { 20, 20 }, t = { 15, 15 } } },
  -- KPz 70（11-28）：间隔装甲，车体正面约 250 毫米当量、侧面 60；炮塔正面约 300；三人车组都在炮塔里（驾驶员在可转的小舱里）、自动装弹机在炮塔尾舱
  kpz70 = { lay = "w4", crew = 3, hull = { f = { 250, 250 }, s = { 60, 60 }, r = { 30, 30 }, t = { 25, 25 } },
    tur = { f = { 300, 300 }, sf = { 200, 200 }, s = { 80, 80 }, r = { 40, 40 }, t = { 30, 30 } } },
  -- T-34-85（11-28）：首上 45 毫米斜 60°（约 90 毫米）、侧面 45 毫米（上半斜 40°）、后 45、顶 20；铸造炮塔正面 90、侧面 75、后 52；
  --   五人车组（车体机枪手），弹在车体底部和炮塔后壁（没有泄压板）
  -- SU-100（11-28）：车体正面 75 毫米斜 50°（视线厚 117）、球形炮盾 110 毫米；侧面 45 毫米斜 20°、后面 45、顶 20；没有炮塔，
  --   「炮塔」那一块是战斗室正面连炮盾（tur：炮盾 / 战斗室前斜面 / 侧面）；四人车组按自行火炮摆（lay spg）
  su100 = { lay = "spg", crew = 4, hull = { f = { 117, 117 }, s = { 48, 48 }, r = { 60, 60 }, t = { 20, 20 } },
    tur = { f = { 130, 130 }, sf = { 117, 117 }, s = { 48, 48 }, r = { 45, 45 }, t = { 20, 20 } } },
  t3485 = { lay = "w4", crew = 5, hull = { f = { 90, 90 }, s = { 55, 55 }, r = { 45, 45 }, t = { 20, 20 } },
    tur = { f = { 100, 100 }, sf = { 80, 80 }, s = { 75, 75 }, r = { 52, 52 }, t = { 20, 20 } } },
  -- 59 式 / 69-II 式（11-26）：首上 100 毫米斜 60°、侧面 80 毫米；铸造炮塔正面 200 毫米；四人车组、弹在炮塔后壁和车体前右（没有泄压板）
  type59 = { lay = "w4", hull = { f = { 200, 200 }, s = { 80, 80 }, r = { 45, 45 }, t = { 30, 30 } },
    tur = { f = { 210, 210 }, sf = { 160, 160 }, s = { 125, 125 }, r = { 65, 65 }, t = { 30, 30 } } },
  type69 = { lay = "w4", hull = { f = { 200, 200 }, s = { 80, 80 }, r = { 45, 45 }, t = { 30, 30 } },
    tur = { f = { 210, 210 }, sf = { 160, 160 }, s = { 125, 125 }, r = { 65, 65 }, t = { 30, 30 } } },
  leo1 = { lay = "w4", hull = { f = { 140, 140 }, s = { 35, 35 }, r = { 25, 25 }, t = { 20, 20 } },          -- 首上 70 毫米斜 60°；没有泄压板
    tur = { f = { 200, 200 }, sf = { 100, 100 }, s = { 60, 60 }, r = { 60, 60 }, t = { 30, 30 } } },
  leo1a5 = { lay = "w4", hull = { f = { 140, 140 }, s = { 35, 35 }, r = { 25, 25 }, t = { 20, 20 } },
    tur = { f = { 300, 350 }, sf = { 140, 160 }, s = { 70, 70 }, r = { 60, 60 }, t = { 30, 30 } } },         -- 炮塔加间隙装甲
  m60a3 = { lay = "w4", hull = { f = { 250, 250 }, s = { 75, 75 }, r = { 40, 40 }, t = { 35, 35 } },         -- 首上 109 毫米斜 65°、铸造炮塔
    tur = { f = { 260, 260 }, sf = { 190, 190 }, s = { 120, 120 }, r = { 60, 60 }, t = { 40, 40 } } },
  m60a1 = { lay = "w4", hull = { f = { 250, 250 }, s = { 75, 75 }, r = { 40, 40 }, t = { 35, 35 } },
    tur = { f = { 250, 250 }, sf = { 180, 180 }, s = { 115, 115 }, r = { 60, 60 }, t = { 40, 40 } } },
  -- 11-27 拆开重叠的版本（估）：M60（1960，首上 93 毫米斜 65°、M48 式的短炮塔——长鼻子炮塔是 M60A1 才换的）、M60A1 RISE（同 M60A1）、
  --   豹 1A1A1（炮塔加了 Blohm + Voss 的间隙装甲，同豹 1A5 的炮塔；车体同豹 1）、豹 2A0（第一代复合装甲）、豹 2A5（同 2A6 的楔形附加装甲）
  m60 = { lay = "w4", hull = { f = { 220, 220 }, s = { 75, 75 }, r = { 40, 40 }, t = { 35, 35 } },
    tur = { f = { 200, 200 }, sf = { 160, 160 }, s = { 110, 110 }, r = { 60, 60 }, t = { 40, 40 } } },
  m60a1rise = { lay = "w4", hull = { f = { 250, 250 }, s = { 75, 75 }, r = { 40, 40 }, t = { 35, 35 } },
    tur = { f = { 250, 250 }, sf = { 180, 180 }, s = { 115, 115 }, r = { 60, 60 }, t = { 40, 40 } } },
  leo1a1a1 = { lay = "w4", hull = { f = { 140, 140 }, s = { 35, 35 }, r = { 25, 25 }, t = { 20, 20 } },
    tur = { f = { 300, 350 }, sf = { 140, 160 }, s = { 70, 70 }, r = { 60, 60 }, t = { 30, 30 } } },
  leo2a0 = { lay = "w4", hull = { f = { 380, 550 }, s = { 70, 90 }, r = { 30, 30 }, t = { 30, 30 } },
    tur = { f = { 450, 750 }, sf = { 230, 280 }, s = { 90, 110 }, r = { 60, 60 }, t = { 40, 40 } }, blowout = true },
  leo2a5 = { lay = "w4", hull = { f = { 560, 850 }, s = { 70, 90 }, r = { 30, 30 }, t = { 30, 30 } },
    tur = { f = { 820, 1300 }, sf = { 300, 350 }, s = { 100, 120 }, r = { 60, 60 }, t = { 45, 45 } }, blowout = true },
  bmp1 = { lay = "ifv", hull = { f = { 33, 33 }, s = { 18, 18 }, r = { 16, 16 }, t = { 6, 6 } }, tur = { f = { 23, 23 }, s = { 19, 19 }, r = { 13, 13 }, t = { 6, 6 } } },
  type86 = { lay = "ifv", hull = { f = { 33, 33 }, s = { 18, 18 }, r = { 16, 16 }, t = { 6, 6 } }, tur = { f = { 23, 23 }, s = { 19, 19 }, r = { 13, 13 }, t = { 6, 6 } } },   -- 11-27：86 式（同 BMP-1）
  bmp2 = { lay = "ifv", hull = { f = { 35, 35 }, s = { 18, 18 }, r = { 16, 16 }, t = { 6, 6 } }, tur = { f = { 33, 33 }, s = { 23, 23 }, r = { 13, 13 }, t = { 8, 8 } } },
  bmp2m = { lay = "ifv", hull = { f = { 35, 35 }, s = { 18, 18 }, r = { 16, 16 }, t = { 6, 6 } }, tur = { f = { 33, 33 }, s = { 23, 23 }, r = { 13, 13 }, t = { 8, 8 } } },
  -- 黄鼠狼 1A3（11-28）：加了附加装甲的车体正面挡 30 毫米（视线厚约 70）、侧面 35（带裙板）、后面 20、顶 15；炮塔正面 45、侧面 25
  marder1a3 = { lay = "ifv", crew = 3, hull = { f = { 70, 70 }, s = { 35, 35 }, r = { 20, 20 }, t = { 15, 15 } }, tur = { f = { 45, 45 }, s = { 25, 25 }, r = { 20, 20 }, t = { 15, 15 } } },
  m2a3 = { lay = "ifv", hull = { f = { 80, 120 }, s = { 40, 60 }, r = { 20, 20 }, t = { 20, 20 } }, tur = { f = { 60, 60 }, s = { 30, 30 }, r = { 20, 20 }, t = { 20, 20 } } },
  -- 11-27 拆开重叠的版本（估）：M2（1981，铝合金车体 + 间隙钢板，正面挡 14.5 毫米）、M2A2（1988，加挂钢装甲，正面挡 30 毫米脱壳弹）
  m2a0 = { lay = "ifv", hull = { f = { 45, 45 }, s = { 30, 30 }, r = { 20, 20 }, t = { 20, 20 } }, tur = { f = { 35, 35 }, s = { 25, 25 }, r = { 20, 20 }, t = { 20, 20 } } },
  m2a2 = { lay = "ifv", hull = { f = { 75, 110 }, s = { 40, 60 }, r = { 20, 20 }, t = { 20, 20 } }, tur = { f = { 55, 55 }, s = { 30, 30 }, r = { 20, 20 }, t = { 20, 20 } } },
  hmmwv = { lay = "light", hull = { f = { 8, 8 }, s = { 6, 6 }, r = { 5, 5 }, t = { 4, 4 } }, crew = 2 },
  jltv = { lay = "light", hull = { f = { 15, 15 }, s = { 12, 12 }, r = { 10, 10 }, t = { 8, 8 } }, crew = 2 },
  pgz07 = { lay = "spg", hull = { f = { 30, 30 }, s = { 20, 20 }, r = { 15, 15 }, t = { 15, 15 } }, tur = { f = { 25, 25 }, s = { 15, 15 }, r = { 12, 12 }, t = { 10, 10 } }, crew = 4 },
  gepard1a1 = { lay = "spg", hull = { f = { 140, 140 }, s = { 35, 35 }, r = { 25, 25 }, t = { 20, 20 } }, tur = { f = { 40, 40 }, s = { 20, 20 }, r = { 15, 15 }, t = { 10, 10 } }, crew = 3 },   -- 豹 1 车体
  gepard1a2 = { lay = "spg", hull = { f = { 140, 140 }, s = { 35, 35 }, r = { 25, 25 }, t = { 20, 20 } }, tur = { f = { 40, 40 }, s = { 20, 20 }, r = { 15, 15 }, t = { 10, 10 } }, crew = 3 },
  m163 = { lay = "spg", hull = { f = { 30, 30 }, s = { 25, 25 }, r = { 15, 15 }, t = { 15, 15 } }, tur = { f = { 12, 12 }, s = { 12, 12 }, r = { 12, 12 }, t = { 8, 8 } }, crew = 2 },
  pgl625 = { lay = "spg", hull = { f = { 12, 12 }, s = { 10, 10 }, r = { 8, 8 }, t = { 6, 6 } }, tur = { f = { 15, 15 }, s = { 10, 10 }, r = { 8, 8 }, t = { 6, 6 } }, crew = 3 },
  pantsir = { lay = "spg", hull = { f = { 15, 15 }, s = { 10, 10 }, r = { 8, 8 }, t = { 6, 6 } }, tur = { f = { 15, 15 }, s = { 10, 10 }, r = { 8, 8 }, t = { 6, 6 } }, crew = 3 },
  ld2000 = { lay = "spg", hull = { f = { 12, 12 }, s = { 10, 10 }, r = { 8, 8 }, t = { 6, 6 } }, tur = { f = { 15, 15 }, s = { 10, 10 }, r = { 8, 8 }, t = { 6, 6 } }, crew = 3 },
  mshorad = { lay = "apc", hull = { f = { 35, 35 }, s = { 20, 20 }, r = { 15, 15 }, t = { 12, 12 } }, tur = { f = { 20, 20 }, s = { 15, 15 }, r = { 12, 12 }, t = { 10, 10 } }, crew = 3 },
  -- 11-27 补的三型（视线方向的等效厚度，毫米）：87 式侦察警戒车（82 式的钢装甲车体，正面挡 12.7 毫米、四周挡 7.62 毫米；车组按炮塔两人 + 驾驶员算）、
  --   BRDM-2（首上 14 毫米斜置、侧后 7 毫米，发动机在后：ifvr；锥形炮塔 7 毫米）、箭-1（同 BRDM-2 车体，转台、发射架很薄，弹在发射架上：spg）
  type87rcv = { lay = "apc", hull = { f = { 20, 20 }, s = { 10, 10 }, r = { 8, 8 }, t = { 6, 6 } }, tur = { f = { 16, 16 }, s = { 10, 10 }, r = { 8, 8 }, t = { 6, 6 } }, crew = 3 },
  brdm2 = { lay = "ifvr", hull = { f = { 22, 22 }, s = { 7, 7 }, r = { 7, 7 }, t = { 7, 7 } }, tur = { f = { 9, 9 }, s = { 7, 7 }, r = { 7, 7 }, t = { 7, 7 } }, crew = 3 },
  strela1 = { lay = "spg", hull = { f = { 22, 22 }, s = { 7, 7 }, r = { 7, 7 }, t = { 7, 7 } }, tur = { f = { 6, 6 }, s = { 5, 5 }, r = { 5, 5 }, t = { 5, 5 } }, crew = 3 },
  cram = { lay = "spg", hull = { f = { 10, 10 }, s = { 8, 8 }, r = { 8, 8 }, t = { 6, 6 } }, tur = { f = { 10, 10 }, s = { 8, 8 }, r = { 8, 8 }, t = { 6, 6 } }, crew = 2 },
  plz07 = { lay = "spg", hull = { f = { 40, 40 }, s = { 25, 25 }, r = { 20, 20 }, t = { 15, 15 } }, tur = { f = { 30, 30 }, s = { 20, 20 }, r = { 15, 15 }, t = { 12, 12 } }, crew = 4 },
  m109a7 = { lay = "spg", hull = { f = { 40, 40 }, s = { 30, 30 }, r = { 20, 20 }, t = { 15, 15 } }, tur = { f = { 30, 30 }, s = { 25, 25 }, r = { 15, 15 }, t = { 12, 12 } }, crew = 4 },
  m270 = { lay = "spg", hull = { f = { 30, 30 }, s = { 20, 20 }, r = { 15, 15 }, t = { 10, 10 } }, tur = { f = { 15, 15 }, s = { 10, 10 }, r = { 10, 10 }, t = { 8, 8 } }, crew = 3 },
  patriot = { lay = "light", hull = { f = { 10, 10 }, s = { 8, 8 }, r = { 8, 8 }, t = { 6, 6 } }, crew = 2 },
}
-- 没登记的型号按类别给一套
W.CAT = {
  tank = { lay = "w4", hull = { f = { 450, 600 }, s = { 70, 80 }, r = { 35, 35 }, t = { 30, 30 } }, tur = { f = { 500, 700 }, sf = { 200, 250 }, s = { 80, 90 }, r = { 50, 50 }, t = { 35, 35 } } },
  apc = { lay = "apc", hull = { f = { 30, 30 }, s = { 18, 18 }, r = { 12, 12 }, t = { 10, 10 } }, tur = { f = { 25, 25 }, s = { 15, 15 }, r = { 12, 12 }, t = { 10, 10 } } },
  aa = { lay = "spg", hull = { f = { 20, 20 }, s = { 15, 15 }, r = { 10, 10 }, t = { 8, 8 } }, tur = { f = { 15, 15 }, s = { 10, 10 }, r = { 10, 10 }, t = { 8, 8 } }, crew = 3 },
  arty = { lay = "spg", hull = { f = { 30, 30 }, s = { 20, 20 }, r = { 15, 15 }, t = { 12, 12 } }, tur = { f = { 25, 25 }, s = { 15, 15 }, r = { 12, 12 }, t = { 10, 10 } }, crew = 4 },
}
function W.prof(d)
  return W.PROF[d.id] or W.CAT[d.cat] or W.CAT.apc
end

---------------------------------------------------------------- 弹放在车体底下转盘式自动装弹机里的车
-- 苏 / 俄 T-64、T-72、T-80、T-90，中国 96、99 系。11-26 起（用户「部分弹药架在下面的坦克被干掉炮塔飞起来吧 然后要先着火再飞」）只有它们殉爆掀炮塔、
--   先烧几秒；11-28 晚起（用户「坦克被穿透关键部位要直接爆 炮塔炮管子都要崩飞」）哪种坦克殉爆都一打中就炸、掀炮塔、炮管单独崩飞（View.lua）——
--   这张表现在只给测试、资料卡认「弹在车体底下」
W.CAROUSEL = { t64a = true, t64b = true, t72ural = true, t72a = true, t72b = true, t72b3 = true, t80b = true, t80u = true, t80bvm = true,
  t90m = true, t90a = true, ztz96 = true, ztz99a = true,
  ztz96base = true, ztz96a = true, ztz99base = true }   -- 11-27 拆出来的 96 式、96A、99 式（同样是车体底下的转盘式自动装弹机）
-- 烧多久（2.2～3.4 秒）：按实体编号定，服务器、各个客户端算出来一样
-- 11-28 晚起殉爆不再先烧（用户「坦克被穿透关键部位要直接爆」）：0 秒。函数留着（测试、老脚本按它算等多久）
function W.cookSecs(id)
  local _ = id
  return 0
end

---------------------------------------------------------------- 弹的穿深（毫米）

-- 坦克炮弹（Ballistics.AMMO 的键）：p0 炮口处、fall 每公里掉多少（脱壳穿甲弹）、t 类型（ke 动能 / ce 聚能 / he 杀爆）、
--   spall 破片锥半角（度）、n 破片数、core 弹芯 / 射流往里钻多远（米）、tandem 串联装药（爆反挡不住）
W.AMMO = {
  refleks = { p0 = 850, t = "ce", spall = 20, n = 14, core = 2.6, tandem = true },   -- 9M119M「反射」炮射导弹
  m829a3 = { p0 = 800, fall = 30, t = "ke", spall = 16, n = 16, core = 3.2 },
  m830 = { p0 = 600, t = "ce", spall = 20, n = 12, core = 2.4 },
  m830a1 = { p0 = 500, t = "ce", spall = 22, n = 12, core = 2.0 },
  m1028 = { p0 = 15, t = "he", spall = 30, n = 0, core = 0 },
  m900 = { p0 = 560, fall = 30, t = "ke", spall = 16, n = 14, core = 3.0 },
  m456 = { p0 = 430, t = "ce", spall = 20, n = 10, core = 2.0 },
  dtc10 = { p0 = 760, fall = 30, t = "ke", spall = 16, n = 16, core = 3.2 },
  heat125 = { p0 = 550, t = "ce", spall = 20, n = 12, core = 2.2 },
  he125 = { p0 = 45, t = "he", spall = 40, n = 20, core = 0, blast = 2.4 },
  bm60 = { p0 = 720, fall = 30, t = "ke", spall = 16, n = 16, core = 3.2 },
  bk31 = { p0 = 760, t = "ce", spall = 20, n = 12, core = 2.4, tandem = true },
  of26 = { p0 = 45, t = "he", spall = 40, n = 20, core = 0, blast = 2.4 },
  -- 金属射流弹：串联聚能装药（穿深跟距离无关、爆反挡不住多少），射流在车里钻得深（core 米）、破片锥窄而密
  jet120 = { p0 = 900, t = "ce", spall = 16, n = 18, core = 4.2, tandem = true, jet = true },
  jet125 = { p0 = 950, t = "ce", spall = 16, n = 18, core = 4.4, tandem = true, jet = true },
  jet105 = { p0 = 760, t = "ce", spall = 16, n = 16, core = 3.8, tandem = true, jet = true },
  bm42 = { p0 = 560, fall = 30, t = "ke", spall = 16, n = 16, core = 3.0 },
  bm22 = { p0 = 440, fall = 35, t = "ke", spall = 16, n = 14, core = 2.8 },
  bm15 = { p0 = 410, fall = 40, t = "ke", spall = 16, n = 14, core = 2.8 },
  bk18m = { p0 = 550, t = "ce", spall = 20, n = 12, core = 2.2 },
  dm53 = { p0 = 740, fall = 30, t = "ke", spall = 16, n = 16, core = 3.2 },
  dm33 = { p0 = 520, fall = 30, t = "ke", spall = 16, n = 16, core = 3.0 },
  dm12 = { p0 = 480, t = "ce", spall = 22, n = 12, core = 2.0 },
  dm13 = { p0 = 290, fall = 55, t = "ke", spall = 14, n = 12, core = 2.6 },
  dm33l7 = { p0 = 420, fall = 35, t = "ke", spall = 16, n = 14, core = 3.0 },
  dm12h = { p0 = 400, t = "ce", spall = 20, n = 10, core = 2.0 },
  m833 = { p0 = 440, fall = 35, t = "ke", spall = 16, n = 14, core = 3.0 },
  m392 = { p0 = 300, fall = 55, t = "ke", spall = 14, n = 12, core = 2.6 },
  m409 = { p0 = 500, t = "ce", spall = 24, n = 12, core = 2.4 },   -- M551 的 152 毫米多用途破甲弹（主炮的弹种按这张表查；W.WPN 里那份留给按武器查的）
  xm578 = { p0 = 360, fall = 30, t = "ke", spall = 14, n = 10, core = 1.8 },   -- KPz 70：XM578（10 米 360 毫米上下）
  br365 = { p0 = 145, fall = 40, t = "ke", spall = 18, n = 12, core = 2.0 },    -- T-34-85：BR-365（10 米 145 毫米，1 公里 115 上下）
  br365p = { p0 = 194, fall = 95, t = "ke", spall = 12, n = 8, core = 1.6 },    -- BR-365P 次口径：近处 194，掉得快（1 公里 100 上下）
  o365 = { p0 = 25, t = "he", spall = 35, n = 16, core = 0, blast = 2.0 },
  br412 = { p0 = 195, fall = 40, t = "ke", spall = 24, n = 16, core = 2.4 },    -- SU-100：BR-412 尖头穿甲榴弹（10 米 195 毫米上下；带装药，破片多一点）
  br412d = { p0 = 200, fall = 45, t = "ke", spall = 20, n = 14, core = 2.4 },   -- 59 式：钝头穿甲弹（1 公里 175 毫米上下）
  bk5m = { p0 = 380, t = "ce", spall = 22, n = 12, core = 2.0 },
  of412 = { p0 = 30, t = "he", spall = 40, n = 18, core = 0, blast = 2.2 },
  apfsds69 = { p0 = 330, fall = 35, t = "ke", spall = 16, n = 14, core = 2.8 },   -- 69-II 式尾翼稳定脱壳穿甲弹
  -- 11-27 拆开重叠的版本：M1 一族照年代的弹（炮口穿深，估：同一个比例尺，M829A3 = 800）
  m774 = { p0 = 400, fall = 35, t = "ke", spall = 16, n = 14, core = 2.9 },     -- M1 的 105 毫米贫铀长杆
  m735 = { p0 = 350, fall = 35, t = "ke", spall = 16, n = 14, core = 2.8 },     -- 105 毫米钨合金（M1、M60A1 RISE）
  m829 = { p0 = 560, fall = 30, t = "ke", spall = 16, n = 16, core = 3.0 },
  m829a1 = { p0 = 640, fall = 30, t = "ke", spall = 16, n = 16, core = 3.1 },   -- 「银弹」
  m829a2 = { p0 = 700, fall = 30, t = "ke", spall = 16, n = 16, core = 3.1 },
  m829a4 = { p0 = 880, fall = 28, t = "ke", spall = 16, n = 16, core = 3.3 },   -- SEPv3（弹药数据链）
  dm13l44 = { p0 = 420, fall = 35, t = "ke", spall = 16, n = 14, core = 2.9 },  -- 豹 2A0 的 120 毫米 DM13
  dtw125 = { p0 = 480, fall = 35, t = "ke", spall = 16, n = 14, core = 2.9 },   -- 96 式 DTW-125 I 型（估）
  dtw125b = { p0 = 600, fall = 30, t = "ke", spall = 16, n = 16, core = 3.0 },  -- 96A、99 式 DTW-125 II 型（估）
}
-- 别的武器（按武器 id）：机炮的脱壳穿甲弹、反坦克火箭 / 导弹、飞机的弹
W.WPN = {
  ac30 = { p0 = 70, fall = 25, t = "ke", spall = 18, n = 4, core = 1.2 },      -- 30 毫米（2A72 / Mk44）脱壳穿甲弹
  ac35 = { p0 = 60, fall = 25, t = "ke", spall = 18, n = 4, core = 1.0 },
  ac25 = { p0 = 62, fall = 22, t = "ke", spall = 18, n = 4, core = 1.1 },      -- 87 式的 KBA 25 毫米脱壳穿甲曳光弹（1 公里约 50 毫米）
  kpvt = { p0 = 40, fall = 16, t = "ke", spall = 10, n = 2, core = 0.5 },      -- BRDM-2 的 KPVT 14.5 毫米 B-32 穿甲燃烧弹（500 米约 32 毫米）
  ac30aa = { p0 = 55, fall = 25, t = "ke", spall = 18, n = 3, core = 1.0 },
  vulcan = { p0 = 30, fall = 20, t = "ke", spall = 18, n = 2, core = 0.6 },
  gau8 = { p0 = 75, fall = 25, t = "ke", spall = 18, n = 5, core = 1.4 },      -- A-10 的 30 毫米贫铀穿甲弹
  gun100 = { p0 = 40, t = "he", spall = 40, n = 18, core = 0, blast = 2.2 },    -- BMP-3 的 100 毫米榴弹
  gun73 = { p0 = 300, t = "ce", spall = 20, n = 10, core = 1.8 },
  m409 = { p0 = 500, t = "ce", spall = 24, n = 12, core = 2.4 },   -- M551 的 152 毫米多用途破甲弹
  tow2 = { p0 = 900, t = "ce", spall = 20, n = 14, core = 2.6, tandem = true },   -- 陶式 2A 串联破甲（前级引爆爆反）
  tow1 = { p0 = 600, t = "ce", spall = 20, n = 12, core = 2.2 },                  -- 11-27：M2 的 BGM-71C 改进型陶式（单装药，估）
  hj73 = { p0 = 425, t = "ce", spall = 20, n = 10, core = 1.8 },                  -- 11-27：86 式的红箭-73（仿 9M14，估）
  -- 11-27：M2 / M2A2 的 M242 25 毫米 M791 脱壳穿甲曳光弹。二审：原来每公里掉 16（1 公里 60、2 公里 44），掉得比公开数快——
  --   估（照战雷，同下面 M919）：战雷 wiki 1 公里 66～67、2 公里 55～56 毫米（钢铁猛兽数据表 2 公里 60）→ 炮口 76、每公里掉 10：66 / 56
  m242 = { p0 = 76, fall = 10, t = "ke", spall = 18, n = 4, core = 1.1 },
  m242m919 = { p0 = 100, fall = 14, t = "ke", spall = 18, n = 5, core = 1.2 },   -- 11-27：M2A3 的 M242 打 M919 贫铀长杆（估：同战雷，炮口约 100、2 公里约 74 毫米）
  malyutka = { p0 = 400, t = "ce", spall = 20, n = 10, core = 1.8 },
  konkurs = { p0 = 600, t = "ce", spall = 20, n = 12, core = 2.2 },               -- 9M113「竞技」
  kornet = { p0 = 1100, t = "ce", spall = 22, n = 14, core = 2.8, tandem = true },   -- 9M133「短号」串联破甲              -- 9M14「婴儿」             -- BMP-1 的 73 毫米 PG-15V 破甲弹
  hmg = { p0 = 25, fall = 10, t = "ke", spall = 10, n = 1, core = 0.4 },       -- 12.7 毫米穿甲弹
  rpg = { p0 = 500, t = "ce", spall = 22, n = 10, core = 1.8 },                -- 火箭筒（RPG-7 / PF-98 一类的串联破甲）
  c4 = { p0 = 120, t = "he", spall = 40, n = 14, core = 0, blast = 2.6 },
  manpads = { p0 = 40, t = "he", spall = 30, n = 6, core = 0, blast = 1.4 },
  s57e6 = { p0 = 40, t = "he", spall = 30, n = 6, core = 0, blast = 1.6 },
  s9m31 = { p0 = 30, t = "he", spall = 30, n = 5, core = 0, blast = 1.3 },     -- 箭-1 的 9M31（2.6 公斤破片战斗部）
}
-- 按武器的种类给（上面两张表都没有的）：导弹、火箭弹按破甲弹，炸弹、炮弹按杀爆
W.KIND = {
  agm = { p0 = 900, t = "ce", spall = 20, n = 14, core = 2.6 },     -- 空地导弹（地狱火、AKD-10 一类）
  missile = { p0 = 800, t = "ce", spall = 20, n = 12, core = 2.4 },
  rkt = { p0 = 120, t = "ce", spall = 22, n = 6, core = 1.0 },       -- 航空火箭弹
  rocket = { p0 = 120, t = "ce", spall = 22, n = 6, core = 1.0 },
  bomb = { p0 = 80, t = "he", spall = 45, n = 24, core = 0, blast = 4.0 },
  arty = { p0 = 50, t = "he", spall = 40, n = 18, core = 0, blast = 3.0 },
  mortar = { p0 = 25, t = "he", spall = 40, n = 10, core = 0, blast = 2.0 },
  shell = { p0 = 40, t = "he", spall = 40, n = 12, core = 0, blast = 2.2 },
  gun = { p0 = 8, fall = 5, t = "ke", spall = 0, n = 0, core = 0 },
}
-- 这一发的穿深：返回（毫米，表项）；distM 飞了多少米
-- 车上的武器表（VehDefs.W）没有 id 字段（飞机、舰艇、工事的有）：按表反查它在 VehDefs.W 里的键，W.WPN 才认得
--   （原来车载的 30 毫米炮、73 / 100 毫米炮都落到通用的「炮弹」40 毫米榴弹上）
local vehWid
local function widOf(w)
  if not vehWid then
    vehWid = {}
    local ok, VD = pcall(function() return require(script.Parent:FindFirstChild("VehDefs")) end)
    if ok and type(VD) == "table" and VD.W then
      for k, t in pairs(VD.W) do vehWid[t] = k end
    end
  end
  return w and vehWid[w]
end
function W.ammoOf(w)
  if not w then return W.KIND.gun end
  return (w.ammo and W.AMMO[w.ammo]) or (w.id and W.WPN[w.id]) or (w.base and w.base.id and W.WPN[w.base.id])
    or W.WPN[widOf(w) or ""] or W.WPN[widOf(w.base) or ""] or W.KIND[w.kind] or W.KIND.gun
end
function W.pen(w, distM)
  local a = W.ammoOf(w)
  local p = a.p0
  if a.fall and distM then p = math.max(a.p0 * 0.4, a.p0 - a.fall * distM / 1000) end
  return p, a
end
-- 单装药的聚能装药（爆反照挡火箭弹那样挡：TankMods.ERA 的 k，不是串联的 kt）：这一发自己登记的表项（W.AMMO / W.WPN）是破甲、又没写 tandem——
--   陶式 1（tow1）、红箭-73（hj73）、「婴儿」（malyutka）、「竞技」（konkurs）；串联的（陶式 2、「短号」、「反射」）、
--   只有按种类给的通用表项（飞机的空地导弹，不知道是哪种）都不算（11-27：原来 Era.lua 对导弹一律按串联算）
function W.singleCharge(w)
  local a = W.ammoOf(w)
  if a.t ~= "ce" or a.tandem then return false end
  for _, g in pairs(W.KIND) do
    if g == a then return false end
  end
  return true
end

---------------------------------------------------------------- 车里的乘员和模块（按型号的尺寸摆，缓存）

-- 每件：k 名字、kind crew / mod、role（乘员）、lo / hi 盒子（格）、tur 在炮塔系、hp 满血、ext 车外的（履带、炮管：没击穿也能打坏）
local cache = {}
local CREW = { drv = "drv", gnr = "gnr", cmd = "cmd", ldr = "ldr" }
W.ROLES = { "drv", "gnr", "cmd", "ldr" }
function W.layout(d)
  local hit = cache[d]
  if hit then return hit end
  local P = W.prof(d)
  local L, Wd, H = d.L, d.W, d.H
  local hH = d.hullH or H * 0.55
  local cl = d.clear or 1.2
  local fl = cl + 0.25              -- 车体底板（里面）
  local list = {}
  local function add(k, kind, lo, hi, extra)
    local it = { k = k, kind = kind, lo = lo, hi = hi, hp = (kind == "crew") and 100 or 100 }
    if extra then for a, b in pairs(extra) do it[a] = b end end
    table.insert(list, it)
    return it
  end
  local function crew(role, c, tur)   -- 一个人：约 0.6 × 0.95 × 0.6 米（坐着）
    return add(role, "crew", c - V(0.85, 1.35, 0.85), c + V(0.85, 1.35, 0.85), { role = role, tur = tur })
  end
  local T = d.turret
  local tp = T and T.pivot or V(0, hH, 0)
  local ts = T and T.size or V(Wd * 0.6, 2, L * 0.4)
  local bus = T and T.bustle or 0
  local lay = P.lay
  local nCrew = P.crew or ((lay == "w4") and 4 or 3)
  local front, back = -L / 2, L / 2
  -- 履带 / 车轮（车外，侧面下半截）：打坏了动不了
  for s = -1, 1, 2 do
    local x0, x1 = s * (Wd / 2 - Wd * 0.13), s * (Wd / 2)
    add(s > 0 and "trackR" or "trackL", "mod", V(math.min(x0, x1), 0, front + 0.5), V(math.max(x0, x1), cl + 1.2, back - 0.5), { ext = true })
  end
  -- 炮管（炮塔系，在外面）、炮闩
  if d.gun and T then
    local gp = d.gun.pivot
    local cal = math.max(0.25, (d.gun.cal or 0.3))
    local len = d.gun.len or 8
    add("barrel", "mod", V(gp.X - cal, gp.Y - cal, gp.Z - len), V(gp.X + cal, gp.Y + cal, gp.Z - 1.2), { tur = true, ext = true })
    add("breech", "mod", V(gp.X - 0.7, gp.Y - 0.65, gp.Z - 0.4), V(gp.X + 0.7, gp.Y + 0.55, gp.Z + 2.6), { tur = true })
    -- 方向机（用户 11-28「方向机也要能被打坏」）：座圈前面、炮长那一侧（西方坦克炮长在右，苏式、步战车在左），
    --   电机 + 减速箱约 0.5 米见方，下半截在座圈以下（原来只有 1 格见方 ≈ 0.36 米，几乎打不着）
    local sd = (lay == "w4") and 1 or -1
    local rr = math.clamp(math.min(ts.X, ts.Z) * 0.36, 1.2, Wd * 0.36)
    local tc = V(sd * rr * 0.62, -0.35, -rr * 0.74)
    add("tdrive", "mod", tc - V(0.7, 0.65, 0.7), tc + V(0.7, 0.65, 0.7), { tur = true })
  end
  local engFront = (lay == "ifv" or lay == "apc" or lay == "light")   -- 发动机在前面的
  if engFront then
    local xs = (lay == "light") and -Wd * 0.3 or Wd * 0.04   -- 步战车：发动机在右前（驾驶员在左前）
    add("engine", "mod", V(xs, fl, front + L * 0.05), V(Wd * 0.36, hH - 0.3, front + L * 0.3))
    add("trans", "mod", V(-Wd * 0.3, fl, front + 0.3), V(Wd * 0.36, fl + 1.2, front + L * 0.06))
  else
    add("engine", "mod", V(-Wd * 0.32, fl, back - L * 0.3), V(Wd * 0.32, hH - 0.35, back - L * 0.08))
    add("trans", "mod", V(-Wd * 0.34, fl, back - L * 0.08), V(Wd * 0.34, fl + 1.3, back - 0.35))
  end
  -- 乘员
  local yS = fl + 1.35   -- 坐着的人中心离底板
  if lay == "w4" then
    crew("drv", V(0, yS, front + L * 0.16))
    crew("gnr", V(1.35, -0.55, -0.9), true)     -- 炮长在右前（炮塔系，y 相对座圈：往下坐进车体）
    crew("cmd", V(1.5, 0.35, 0.9), true)        -- 车长在炮长后上
    crew("ldr", V(-1.45, -0.35, 0.1), true)     -- 装填手在左
    -- 弹：炮塔尾舱（有泄压板）、车体里少量
    add("ammo", "mod", V(-ts.X * 0.4, 0.3, ts.Z / 2 - math.max(1.5, bus)), V(ts.X * 0.4, ts.Y - 0.4, ts.Z / 2 - 0.2), { tur = true, blow = P.blowout })
    add("ammoH", "mod", V(Wd * 0.12, fl, front + L * 0.2), V(Wd * 0.36, fl + 1.6, front + L * 0.32), {})
    add("fuelL", "mod", V(-Wd * 0.38, fl, front + L * 0.06), V(-Wd * 0.14, hH - 0.4, front + L * 0.24))
    add("fuelR", "mod", V(Wd * 0.14, fl, front + L * 0.06), V(Wd * 0.38, hH - 0.4, front + L * 0.2))
  elseif lay == "e3" then
    crew("drv", V(0, yS - 0.2, front + L * 0.15))
    crew("gnr", V(-1.35, -0.7, -0.4), true)     -- 炮长在左、车长在右（坐得低，炮塔里大半在座圈以下）
    crew("cmd", V(1.35, -0.55, -0.2), true)
    -- 转盘式自动装弹机：车体底板上、炮塔下面一圈（没有泄压，殉爆就是掀炮塔）
    add("ammo", "mod", V(tp.X - Wd * 0.36, fl, tp.Z - Wd * 0.34), V(tp.X + Wd * 0.36, fl + 1.0, tp.Z + Wd * 0.34))
    add("ammoH", "mod", V(Wd * 0.12, fl, front + L * 0.06), V(Wd * 0.38, hH - 0.5, front + L * 0.22))   -- 前右油箱架里的备弹
    add("fuelR", "mod", V(Wd * 0.12, fl, front + L * 0.22), V(Wd * 0.38, hH - 0.5, front + L * 0.32))
  else
    -- 步战车 / 装甲车 / 自行火炮：驾驶员在左前（发动机在前的）或正前（发动机在后的）
    local dx = engFront and -Wd * 0.25 or 0
    crew("drv", V(dx, yS, front + L * 0.16))
    if T and lay ~= "light" then
      crew("gnr", V(-1.2, -0.5, -0.2), true)
      if nCrew >= 3 then crew("cmd", V(1.2, -0.4, 0.2), true) end
      if nCrew >= 4 then crew("ldr", V(0, -0.6, 1.4), true) end
      add("ammo", "mod", V(-ts.X * 0.35, -1.2, 0.4), V(ts.X * 0.35, 0.4, ts.Z / 2 - 0.3), { tur = true })
    else
      if nCrew >= 2 then crew("cmd", V(-dx, yS, front + L * 0.16)) end
      if nCrew >= 3 then crew("gnr", V(0, hH + 0.4, front + L * 0.4)) end   -- 车顶的机枪手
      add("ammo", "mod", V(-Wd * 0.25, fl, front + L * 0.3), V(Wd * 0.25, fl + 1.2, front + L * 0.42))
    end
    add("fuelR", "mod", V(Wd * 0.14, fl, back - L * 0.2), V(Wd * 0.38, hH - 0.4, back - L * 0.05))
    if lay ~= "spg" and lay ~= "light" then   -- 载员舱（后半截）：打进去伤里面坐着的人
      add("troops", "mod", V(-Wd * 0.38, fl, front + L * 0.45), V(Wd * 0.38, hH - 0.3, back - L * 0.06), { troop = true })
    end
  end
  -- 观瞄（用户 11-26「不同部位被击中也要有不同效果……观瞄受损」）：炮长主瞄准镜的镜头（炮塔顶上 d.sight 那里，车外的）——
  --   破片、榴弹、机炮、大口径机枪都打得坏；受损：镜里裂纹、发糊；打坏：只剩最低倍率、热成像没了、裂成一片（客户端 SightDmg.lua），
  --   电脑开的车打坏了观瞄打得不准、发现得慢（AIVeh 按 G.wtOptK）。放在模块表最后（WtM 原来那些位不挪）
  if T and d.sight then
    local sp = d.sight
    add("optics", "mod", V(sp.X - 0.75, sp.Y - 0.45, sp.Z - 0.8), V(sp.X + 0.75, sp.Y + 0.8, sp.Z + 0.8), { tur = true, ext = true })
  end
  -- 高低机（同上，战雷的「垂直驱动」）：炮耳后面、炮闩旁边炮长那一侧；打坏了炮管抬不起也压不下。放在模块表最后（WtM 原来那些位不挪）
  if d.gun and T then
    local gp = d.gun.pivot
    local sd = (lay == "w4") and 1 or -1
    local x0, x1 = gp.X + sd * 0.78, gp.X + sd * 1.8
    add("edrive", "mod", V(math.min(x0, x1), gp.Y - 1.0, gp.Z + 0.15), V(math.max(x0, x1), gp.Y - 0.05, gp.Z + 1.45), { tur = true })
  end
  hit = { list = list, nCrew = nCrew, prof = P, hH = hH, tp = tp, ts = ts }
  cache[d] = hit
  return hit
end

-- 模块 k 在 WtM（服务器写的模块状态串，按布局里模块的顺序一位一位）里是第几位；没有这个模块 nil
function W.modIndex(d, k)
  local i = 0
  for _, it in ipairs(W.layout(d).list) do
    if it.kind ~= "crew" then
      i += 1
      if it.k == k then return i end
    end
  end
  return nil
end
-- 车上模块 k 现在的状态：2 好、1 受损、0 毁了（没有这个模块、还没写属性：2）
function W.modState(em, d, k)
  local i = em and d and W.modIndex(d, k)
  if not i then return 2 end
  local wm = em:GetAttribute("WtM")
  if type(wm) ~= "string" then return 2 end
  return tonumber(string.sub(wm, i, i)) or 2
end

---------------------------------------------------------------- 打在哪、多厚

-- 底座系的点、方向换到炮塔系（炮塔往右转 yaw 度为正，同 VehDefs.turretCF）
function W.toTur(d, p, yaw)
  local tp = d.turret and d.turret.pivot or V()
  local a = math.rad(yaw or 0)
  local c, s = math.cos(a), math.sin(a)
  local q = p - tp
  -- turretCF = base * CF(tp) * Angles(0, −a, 0)：逆变换是绕 y 转 +a（CFrame.Angles(0, θ, 0) 把 x 转到 (cos θ, 0, −sin θ)）
  return V(q.X * c + q.Z * s, q.Y, -q.X * s + q.Z * c)
end
function W.toTurDir(dir, yaw)
  local a = math.rad(yaw or 0)
  local c, s = math.cos(a), math.sin(a)
  return V(dir.X * c + dir.Z * s, dir.Y, -dir.X * s + dir.Z * c)
end
function W.fromTur(d, q, yaw)
  local tp = d.turret and d.turret.pivot or V()
  local a = math.rad(yaw or 0)
  local c, s = math.cos(a), math.sin(a)
  return tp + V(q.X * c - q.Z * s, q.Y, q.X * s + q.Z * c)
end

-- 打中的点（底座系）、来向（底座系，单位向量）、炮塔转角 → 区域 zone（hull / tur）、面 face（f / s / r / t）、弱点系数、法线
function W.where(d, p, dir, yaw)
  local lay = W.layout(d)
  local hH = lay.hH
  local T = d.turret
  if T and p.Y > hH - 0.15 then
    local q = W.toTur(d, p, yaw)
    local ts = lay.ts
    if math.abs(q.X) < ts.X / 2 + 0.6 and q.Z > -ts.Z / 2 - 1.2 and q.Z < ts.Z / 2 + 0.6 then
      local dq = W.toTurDir(dir, yaw)
      local face, n
      -- 按来向在炮塔系里哪个分量最大（盒子的哪一面迎着弹）
      if q.Y > ts.Y - 0.35 and -dq.Y > 0.5 then face, n = "t", V(0, 1, 0)
      elseif math.abs(dq.Z) >= math.abs(dq.X) then
        if dq.Z > 0 then face, n = "f", V(0, 0, -1) else face, n = "r", V(0, 0, 1) end
      else
        face, n = "s", V(dq.X > 0 and -1 or 1, 0, 0)
      end
      local weak = 1
      if face == "f" and math.abs(q.X) < 1.1 and math.abs(q.Y - (d.gun and d.gun.pivot.Y or 1)) < 0.7 then weak = 0.75 end   -- 炮盾
      if (face == "f" or face == "s") and q.Y < 0.45 then weak = math.min(weak, 0.55) end   -- 座圈一带
      if face == "s" and q.Z < 0 then face = "sf" end   -- 炮塔侧面前半截（更厚）
      return "tur", face, weak, n, q, dq
    end
  end
  local face, n
  if p.Y > hH - 0.4 and -dir.Y > 0.55 then face, n = "t", V(0, 1, 0)
  elseif math.abs(dir.Z) >= math.abs(dir.X) then
    if dir.Z > 0 then face, n = "f", V(0, 0, -1) else face, n = "r", V(0, 0, 1) end
  else
    face, n = "s", V(dir.X > 0 and -1 or 1, 0, 0)
  end
  local weak = 1
  local cl = d.clear or 1.2
  if face == "f" and p.Y < cl + (hH - cl) * 0.42 then weak = 0.55 end   -- 首下
  return "hull", face, weak, n, p, dir
end

-- 这一面的装甲（毫米）：ce 破甲弹用化学能那个数
function W.armor(d, zone, face, t)
  local P = W.prof(d)
  local z = (zone == "tur" and P.tur) or P.hull
  local a = z[face] or z.s or z.f
  if not a then return 10 end
  return (t == "ce") and (a[2] or a[1]) or a[1]
end

-- 入射角（度，和法线的夹角）下：等效厚度、会不会跳弹
function W.effective(mm, ang, t)
  local c = math.max(math.cos(math.rad(math.min(ang, 85))), 0.12)
  local eff = mm / c
  if t == "ke" then eff = mm / (c ^ 0.82) end   -- 长杆弹斜着打，转正一点
  return eff
end
function W.ricochet(t, ang)
  local a0, a1
  if t == "ke" then a0, a1 = 74, 82 elseif t == "ce" then a0, a1 = 78, 84 else a0, a1 = 66, 78 end
  return math.clamp((ang - a0) / (a1 - a0), 0, 1)
end

-- 一根射线（底座系起点、方向、长度）穿过的零件：{ { it, t 进入时离起点多远 }, … } 按远近
local function slab(o, dv, lo, hi, len)
  local t0, t1 = 0, len
  for _, ax in ipairs({ "X", "Y", "Z" }) do
    local oo, dd, l, h = o[ax], dv[ax], lo[ax], hi[ax]
    if math.abs(dd) < 1e-6 then
      if oo < l or oo > h then return nil end
    else
      local a, b = (l - oo) / dd, (h - oo) / dd
      if a > b then a, b = b, a end
      if a > t0 then t0 = a end
      if b < t1 then t1 = b end
      if t0 > t1 then return nil end
    end
  end
  return t0
end
function W.trace(d, yaw, o, dv, len, skipExt)
  local lay = W.layout(d)
  local out = {}
  local oT, dT = W.toTur(d, o, yaw), W.toTurDir(dv, yaw)
  for _, it in ipairs(lay.list) do
    if not (skipExt and it.ext) then
      local t = it.tur and slab(oT, dT, it.lo, it.hi, len) or slab(o, dv, it.lo, it.hi, len)
      if t then table.insert(out, { it = it, t = t }) end
    end
  end
  table.sort(out, function(a, b) return a.t < b.t end)
  return out
end
-- 点在不在零件盒子里（底座系）
function W.inside(d, yaw, p, it, pad)
  pad = pad or 0
  local q = it.tur and W.toTur(d, p, yaw) or p
  return q.X >= it.lo.X - pad and q.X <= it.hi.X + pad and q.Y >= it.lo.Y - pad and q.Y <= it.hi.Y + pad and q.Z >= it.lo.Z - pad and q.Z <= it.hi.Z + pad
end
-- 零件中心（底座系；炮塔上的按现在的炮塔转角）
function W.center(d, yaw, it)
  local c = (it.lo + it.hi) / 2
  return it.tur and W.fromTur(d, c, yaw) or c
end

-- 一锥破片的方向（确定的伪随机：服务器、客户端回放画出来一样）：axis 弹道方向、half 半角（度）、n 根、seed
function W.cone(axis, half, n, seed)
  local out = {}
  local up = math.abs(axis.Y) < 0.9 and V(0, 1, 0) or V(1, 0, 0)
  local r1 = axis:Cross(up).Unit
  local r2 = axis:Cross(r1).Unit
  local s = (seed or 1) % 2147483647
  local function rnd() s = (s * 16807) % 2147483647 return s / 2147483647 end
  for i = 1, n do
    local a = rnd() * math.pi * 2
    local t = math.rad(half) * math.sqrt(rnd())
    local dv = (axis * math.cos(t) + (r1 * math.cos(a) + r2 * math.sin(a)) * math.sin(t)).Unit
    out[i] = dv
  end
  return out
end

-- 名字（客户端界面）：模块 / 乘员的中文名用 Lang 的 wt.<k>
W.MODS = { "engine", "trans", "trackL", "trackR", "barrel", "breech", "tdrive", "ammo", "ammoH", "fuelL", "fuelR", "troops", "optics", "edrive" }
W.M = M
return W
