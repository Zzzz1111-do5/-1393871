-- 全面大战场（共用）——科技树（用户 11-25：「从1960到现代的战机和坦克 科技树」「再去做一个中 德 美 日 俄系」，发了战雷科技树的截图）
--   五个系（中、德、美、日、俄）× 两棵树（地面：坦克等；空中：喷气式战机），按年代分七级、每级一行，按车种分列，同一列上下连线（前置）。
--   玩法照战雷那一套（我们自己的数、自己的界面，不照搬名字和美术）：
--   · 研究：打仗挣研究点，记在「正在研究」的那一辆上，攒够这一辆的研究点就研究完；一级里研究完 RANK_NEED 辆才能研究下一级
--   · 购买：研究完以后花金币买下；买下的才能放进出击阵容
--   · 战斗等级 br（0.3 / 0.4 一档）：阵容的战斗等级 = 里面最高的那辆；分房按 ±1.0
--   · 每系每棵树只白送一辆起步车（研究完、买好），按规则现算（TT.starter，见下面「起步车」）；别的都要研究、购买
--   veh：游戏里开的型号（VehDefs / AirDefs 的 id）。base：还没有自己的模型和性能，先借这一辆的（界面上写「暂用 某某」，以后做了真模型就换成 veh）
local TT = {}

TT.NATIONS = { "cn", "de", "us", "jp", "ru" }
TT.NAT = {
  cn = { name = "中国", en = "China", col = Color3.fromRGB(196, 64, 52) },
  de = { name = "德国", en = "Germany", col = Color3.fromRGB(120, 120, 120) },
  us = { name = "美国", en = "USA", col = Color3.fromRGB(70, 110, 180) },
  jp = { name = "日本", en = "Japan", col = Color3.fromRGB(220, 220, 220) },
  ru = { name = "俄罗斯", en = "Russia", col = Color3.fromRGB(160, 60, 60) },
}
TT.BRANCHES = { "ground", "air", "heli" }
-- need：一级里研究完几辆才开下一级（没写按 TT.RANK_NEED）；直升机树车少（用户 11-25「直升机也做一下各个国家的」），研究完一架就开下一级
TT.BRANCH = {
  ground = { name = "坦克", en = "Ground", cols = { { "主战坦克", "MBT" }, { "主战坦克 · 第二条线", "MBT II" }, { "轻型 / 歼击车", "Light / TD" },
    { "步兵战车", "IFV" }, { "自行防空", "SPAA" } } },
  air = { name = "战机", en = "Aircraft", cols = { { "战斗机", "Fighters" }, { "重型 / 多用途", "Heavy / Multirole" }, { "攻击机 / 轰炸机", "Strike" } } },
  heli = { name = "直升机", en = "Helicopters", cols = { { "攻击直升机", "Attack" }, { "多用途 / 火力支援", "Utility" } }, need = { 1, 1, 1, 1, 1, 1 } },
}
-- 等级（行）：年代、研究要多少研究点、买要多少金币
TT.RANKS = {
  { roman = "I", years = "1960–1967", rp = 6000, cost = 3000 },
  { roman = "II", years = "1968–1975", rp = 18000, cost = 9000 },
  { roman = "III", years = "1976–1983", rp = 45000, cost = 25000 },
  { roman = "IV", years = "1984–1991", rp = 90000, cost = 60000 },
  { roman = "V", years = "1992–2005", rp = 160000, cost = 120000 },
  { roman = "VI", years = "2006–2015", rp = 240000, cost = 200000 },
  { roman = "VII", years = "2016–", rp = 320000, cost = 300000 },
}
-- 一级里研究完几辆，才能研究下一级（这棵树的）
TT.RANK_NEED = { 3, 3, 3, 2, 2, 2 }

-- 每一项：{ key, 中文名, 英文名, 年份, 等级, 列, 战斗等级, veh = 能开的型号 | base = 暂借的型号, model = 借同族的模型（性能是自己的） }
--   11-25 C 合并：用户 11-24 让删的九辆车（M10 布克、ZBD-05、BMP-3、ZSL-92B、ZTD-05、PTL-02、斯特赖克、M1117、M1150：车内是零件拼的）不在了——
--   原来借它们的、本身就是它们的，按年代和车种改借还在的真模型车：早期 T-55 一类借 M60A1、79 / 88B 借 M60A3、轻坦和歼击车借豹 1 / 1A5、
--   水陆和 BMP 一族借 BMP-1、轮式和导弹车借布雷德利（都写「暂用」，以后做了真模型再换）
--   同一列按顺序：上一项是下一项的前置
--   11-25 用户「内容还不齐，风格不统一」「找不到的你可以直接删掉」：没有原模型的都删了——借别的型号模型的暂用车 / 机
--   （狂风借 F-14、苏-25 借 A-10、59 式借 M60……）、零件拼的（PGZ-07、LD-2000、OH-1……）一共 116 项；留下的每一项要么有自己的原模型，
--   要么借同族、外形几乎一样的（M1 借 M1A1、苏-27 借歼-11、苏-30SM 借歼-16、F-15A / E 借 F-15C、F-2A 借 F-16）。以后找到原模型再加回来
--   德国的固定翼一架都没找到（F-4F、狂风、台风、米格-29G、F-104G 都没有能用的模型），这棵树先空着
local G, A, H = "ground", "air", "heli"
local LIST = {
  cn = {
    [G] = {
      -- 11-26（用户「给各系各阶段缺少的载具都从 sketchfeb 上搞出来」）：一、二级补上 59 式、69-II 式（Sketchfab 的真模型，tools/models/blveh.json type59），
      --   起步车照规则（最低一级、最早的）变成 59 式；96 式不再白送
      { "cn_59", "59式中型坦克", "Type 59", 1959, 1, 1, 6.7, veh = "type59" },
      { "cn_69", "69-II式中型坦克", "Type 69-II", 1982, 2, 1, 7.7, veh = "type69", model = "type59" },
      { "cn_96", "96式主战坦克", "Type 96", 1997, 5, 1, 9.7, base = "ztz96" },
      { "cn_96a", "96A式主战坦克", "Type 96A", 2006, 6, 1, 10.3, base = "ztz96" },
      { "cn_96b", "96B式主战坦克", "Type 96B", 2016, 7, 1, 10.7, veh = "ztz96" },
      { "cn_99", "99式主战坦克", "Type 99", 2001, 5, 2, 10.7, base = "ztz99a" },
      { "cn_99a", "99A式主战坦克", "Type 99A", 2011, 6, 2, 11.7, veh = "ztz99a" },
      { "cn_86", "86式步兵战车", "Type 86", 1986, 4, 4, 7.7, base = "bmp1" },
      { "cn_pgl625", "PGL-625 自行高炮", "PGL-625", 2019, 7, 5, 11.0, veh = "pgl625" },
    },
    [A] = {
      { "cn_j6", "歼-6", "J-6", 1962, 1, 1, 8.0, veh = "j6" },
      { "cn_j10a", "歼-10A", "J-10A", 2004, 5, 1, 12.0, base = "j10" },
      { "cn_j10c", "歼-10C", "J-10C", 2018, 7, 1, 13.3, veh = "j10" },
      { "cn_j8ii", "歼-8II", "J-8II", 1988, 4, 2, 10.7, veh = "j8" },
      { "cn_j11", "歼-11", "J-11", 1998, 5, 2, 12.3, base = "j11" },
      { "cn_j11b", "歼-11B", "J-11B", 2007, 6, 2, 12.7, veh = "j11" },
      { "cn_j16", "歼-16", "J-16", 2015, 6, 2, 13.3, veh = "j16" },
      { "cn_j15t", "歼-15T", "J-15T", 2019, 7, 2, 13.7, veh = "j15t" },
      { "cn_j20", "歼-20", "J-20", 2017, 7, 2, 14.0, veh = "j20" },
      { "cn_j35", "歼-35", "J-35", 2025, 7, 2, 14.0, veh = "j35" },
      { "cn_h6k", "轰-6K", "H-6K", 2011, 6, 3, 11.0, veh = "h6k" },
    },
    [H] = {   -- 中国：直-8（多用途，挂火箭巢）。直-20 借 UH-60 的模型，删了；
      --   直-10 11-27 删了（用户：「直-10（扒的）必须换」——原模型是 42manako 从《战地 3》扒的；Sketchfab 上的直-10 不是扒的就是 NC / 3D 仓库转贴，没有能收的）
      { "cn_z8", "直-8", "Z-8", 1994, 5, 2, 8.3, veh = "z8", free = true },
    },
  },
  de = {
    [G] = {
      { "de_leo1", "豹1", "Leopard 1", 1965, 1, 1, 7.0, veh = "leo1" },
      -- 11-27 拆开重叠的版本（用户「把重叠的版本拆开」「各维度还原一致」）：豹 1A1A1、豹 2A0、豹 2A5 原来写 base，现在各开各的型号、模型借同族的
      { "de_leo1a1a1", "豹1A1A1", "Leopard 1A1A1", 1975, 2, 1, 7.7, veh = "leo1a1a1", model = "leo1" },
      { "de_leo1a5", "豹1A5", "Leopard 1A5", 1987, 4, 1, 8.3, veh = "leo1a5", model = "leo1" },
      { "de_leo2a0", "豹2A0", "Leopard 2A0", 1979, 3, 2, 9.0, veh = "leo2a0", model = "leo2a6" },
      { "de_leo2a4", "豹2A4", "Leopard 2A4", 1985, 4, 2, 9.7, veh = "leo2a4", model = "leo2a6" },
      { "de_leo2a5", "豹2A5", "Leopard 2A5", 1995, 5, 2, 10.7, veh = "leo2a5", model = "leo2a6" },
      { "de_leo2a6", "豹2A6", "Leopard 2A6", 2001, 5, 2, 11.3, veh = "leo2a6" },
      { "de_leo2a7v", "豹2A7V", "Leopard 2A7V", 2020, 7, 2, 12.0, veh = "leo2a7v" },
      { "de_gepard", "猎豹1A1", "Gepard 1A1", 1976, 3, 5, 8.3, veh = "gepard1a1" },
      { "de_gepard1a2", "猎豹1A2", "Gepard 1A2", 1998, 5, 5, 9.3, veh = "gepard1a2" },
    },
    [A] = {
    },
    [H] = {   -- 德国：虎式 UHT（攻击）。NH90 TTH 是纯运输（没有武器），11-26 用户「很多运输型直升机可以去掉了 实战没有意义」删了
      { "de_tiger", "虎式 UHT", "Tiger UHT", 2005, 6, 1, 10.3, veh = "tiger" },
    },
  },
  us = {
    [G] = {
      -- 11-27 拆开重叠的版本：M60、M60A1 RISE 原来写 base（借 M60A1），现在各开各的型号、模型借同族的（M60A3）
      { "us_m60", "M60 巴顿", "M60", 1960, 1, 1, 7.0, veh = "m60", model = "m60a3" },
      { "us_m60a1", "M60A1", "M60A1", 1962, 1, 1, 7.3, veh = "m60a1", model = "m60a3" },
      { "us_m60a1rise", "M60A1 RISE", "M60A1 RISE", 1977, 3, 1, 7.7, veh = "m60a1rise", model = "m60a3" },
      { "us_m60a3", "M60A3 TTS", "M60A3 TTS", 1979, 3, 1, 8.0, veh = "m60a3" },
      -- 11-27 拆开重叠的版本（用户「把重叠的版本拆开（M1A2 / SEP / SEPv3 等）」「各维度还原一致」）：M1 一族原来六项写 base（模型、性能都借 M1A1 / M1A2 SEPv2），
      --   现在各开各的型号（VehDefs：炮、弹、装甲、机动、观瞄照年代），模型借同族的（科技树上写「同族模型」）
      { "us_m1", "M1 艾布拉姆斯", "M1 Abrams", 1980, 3, 2, 9.3, veh = "m1", model = "m1a1" },
      { "us_m1ip", "M1IP", "IPM1", 1984, 4, 2, 9.7, veh = "m1ip", model = "m1a1" },
      { "us_m1a1", "M1A1", "M1A1", 1985, 4, 2, 10.3, veh = "m1a1" },
      { "us_m1a1hc", "M1A1 HC", "M1A1 HC", 1988, 4, 2, 10.7, veh = "m1a1hc", model = "m1a1" },
      { "us_m1a2", "M1A2", "M1A2", 1992, 5, 2, 11.0, veh = "m1a2base", model = "m1a2" },
      { "us_m1a2sep", "M1A2 SEP", "M1A2 SEP", 2000, 5, 2, 11.3, veh = "m1a2sep", model = "m1a2" },
      { "us_m1a2sep2", "M1A2 SEPv2", "M1A2 SEPv2", 2008, 6, 2, 11.7, veh = "m1a2" },
      { "us_m1a2sep3", "M1A2 SEPv3", "M1A2 SEPv3", 2017, 7, 2, 12.0, veh = "m1a2sep3", model = "m1a2" },
      { "us_m551", "M551 谢里登", "M551 Sheridan", 1966, 1, 3, 6.3, veh = "m551" },
      { "us_m2", "M2 布雷德利", "M2 Bradley", 1981, 3, 4, 8.0, base = "m2a3" },
      { "us_m2a2", "M2A2 布雷德利", "M2A2", 1988, 4, 4, 8.7, base = "m2a3" },
      { "us_m2a3", "M2A3 布雷德利", "M2A3", 2000, 5, 4, 9.3, veh = "m2a3" },
      { "us_m163", "M163 火神", "M163 VADS", 1968, 2, 5, 7.0, veh = "m163" },
      { "us_cram", "C-RAM 陆基密集阵", "C-RAM", 2005, 6, 5, 10.0, veh = "cram" },
      { "us_patriot", "爱国者", "Patriot", 2010, 6, 5, 11.3, veh = "patriot" },
      { "us_mshorad", "M-SHORAD", "M-SHORAD", 2020, 7, 5, 11.0, veh = "mshorad" },
    },
    [A] = {
      { "us_f16a", "F-16A 战隼", "F-16A", 1978, 3, 1, 12.0, base = "f16" },
      { "us_f16c", "F-16C 战隼", "F-16C", 1984, 4, 1, 13.0, veh = "f16" },
      { "us_f35a", "F-35A 闪电II", "F-35A", 2016, 7, 1, 14.0, veh = "f35" },
      { "us_f14a", "F-14A 雄猫", "F-14A Tomcat", 1974, 2, 2, 12.0, veh = "f14" },
      { "us_f15a", "F-15A 鹰", "F-15A Eagle", 1976, 3, 2, 12.3, base = "f15" },
      { "us_f15c", "F-15C 鹰", "F-15C Eagle", 1979, 3, 2, 12.7, veh = "f15" },
      { "us_f15e", "F-15E 攻击鹰", "F-15E Strike Eagle", 1988, 4, 2, 13.3, base = "f15" },
      { "us_f22a", "F-22A 猛禽", "F-22A Raptor", 2005, 5, 2, 14.0, veh = "f22" },
      { "us_a10a", "A-10A 雷电II", "A-10A Thunderbolt II", 1977, 3, 3, 10.7, base = "a10c" },
      { "us_b2", "B-2 幽灵", "B-2 Spirit", 1997, 5, 3, 12.0, veh = "b2" },
      { "us_a10c", "A-10C 雷电II", "A-10C Thunderbolt II", 2007, 6, 3, 11.3, veh = "a10c" },
      { "us_mq9", "MQ-9 死神", "MQ-9 Reaper", 2007, 6, 3, 11.0, veh = "mq9" },
    },
    [H] = {   -- 美国：AH-1W、AH-64E（攻击）；UH-1N、UH-60（多用途：火箭巢 / 地狱火）。CH-47 纯运输，11-26 删了（用户：运输直升机实战没有意义）
      { "us_ah1w", "AH-1W 超级眼镜蛇", "AH-1W SuperCobra", 1986, 4, 1, 9.3, veh = "ah1w" },
      { "us_ah64e", "AH-64E 阿帕奇", "AH-64E Apache", 2012, 6, 1, 11.0, veh = "ah64e" },
      { "us_uh1n", "UH-1N 双休伊", "UH-1N Twin Huey", 1971, 2, 2, 7.0, veh = "uh1n" },
      { "us_uh60", "UH-60 黑鹰", "UH-60 Black Hawk", 1979, 3, 2, 8.0, veh = "uh60" },
    },
  },
  jp = {
    [G] = {
      { "jp_type74", "74式主战坦克", "Type 74", 1975, 2, 1, 8.0, veh = "type74" },
      { "jp_type74g", "74式改", "Type 74 (G)", 1993, 4, 1, 8.7, veh = "type74g" },
      { "jp_type10", "10式主战坦克", "Type 10", 2012, 6, 2, 11.3, veh = "type10" },
      -- 11-27（用户「德国目前没飞机 包括很多缺的载具全部做一下」）：「轻型 / 歼击车」一列原来空着，补 87 式侦察警戒车（Sketchfab 真模型，
      --   tools/models/blveh.json type87rcv）；四级这样有两辆，研究六级的 10 式要两辆都研究完
      { "jp_type87rcv", "87式侦察警戒车", "Type 87 RCV", 1987, 4, 3, 7.3, veh = "type87rcv", scout = true },
    },
    [A] = {
      { "jp_f15j", "F-15J 鹰", "F-15J", 1981, 3, 1, 12.3, veh = "f15" },
      { "jp_f15jm", "F-15J（M）", "F-15J (M)", 2007, 6, 1, 13.0, base = "f15" },
      { "jp_f35a", "F-35A 闪电II", "F-35A", 2018, 7, 1, 14.0, veh = "f35" },
      { "jp_f2a", "F-2A", "F-2A", 2000, 5, 3, 12.3, base = "f16" },
    },
    [H] = {   -- 日本：AH-1S、AH-64DJ（攻击；AH-64DJ 借同族的模型）；UH-60JA（多用途，借同族的模型）。OH-1 没有能用的模型，删了；CH-47J 纯运输，11-26 删了
      { "jp_ah1s", "AH-1S 眼镜蛇", "AH-1S Cobra", 1979, 3, 1, 8.7, veh = "ah1s" },
      { "jp_ah64dj", "AH-64DJ", "AH-64DJ", 2006, 6, 1, 10.7, veh = "ah64dj", model = "ah64e" },
      { "jp_uh60ja", "UH-60JA", "UH-60JA", 1997, 5, 2, 8.3, veh = "uh60ja", model = "uh60" },
    },
  },
  ru = {
    [G] = {
      { "ru_t72", "T-72 乌拉尔", "T-72 Ural", 1973, 2, 1, 8.0, veh = "t72ural", model = "t72b3", free = true },   -- T-55 / T-62 没有原模型（删了；11-27 又找了一遍：Sketchfab 上能下的不是扒的就是粗模）
      { "ru_t72a", "T-72A", "T-72A", 1979, 3, 1, 8.7, veh = "t72a", model = "t72b3" },
      { "ru_t72b", "T-72B", "T-72B", 1985, 4, 1, 9.7, veh = "t72b", model = "t72b3" },
      { "ru_t90a", "T-90A", "T-90A", 2004, 5, 1, 10.7, base = "t90m" },
      { "ru_t72b3", "T-72B3", "T-72B3", 2013, 6, 1, 11.0, veh = "t72b3" },
      { "ru_t90m", "T-90M 突破-3", "T-90M", 2020, 7, 1, 12.0, veh = "t90m" },
      { "ru_t64a", "T-64A", "T-64A", 1969, 2, 2, 8.3, veh = "t64a" },
      { "ru_t64b", "T-64B", "T-64B", 1976, 3, 2, 9.3, veh = "t64b" },
      { "ru_t80b", "T-80B", "T-80B", 1978, 3, 2, 9.7, veh = "t80b", model = "t80u" },
      { "ru_t80u", "T-80U", "T-80U", 1985, 4, 2, 10.7, veh = "t80u" },
      { "ru_t80bvm", "T-80BVM", "T-80BVM", 2018, 7, 2, 11.7, veh = "t80bvm", model = "t80u" },
      { "ru_bmp1", "BMP-1", "BMP-1", 1966, 1, 4, 6.7, veh = "bmp1" },
      { "ru_bmp2", "BMP-2", "BMP-2", 1980, 3, 4, 7.7, veh = "bmp2" },
      { "ru_bmp2m", "BMP-2M", "BMP-2M", 2000, 5, 4, 9.3, veh = "bmp2m", model = "bmp2" },
      -- 11-27（用户「很多缺的载具全部做一下」、待办「各系各分支补 1 级车」）：「轻型 / 歼击车」一列原来空着、坦克几列没有 1 级——
      --   补 BRDM-2（1 级，Sketchfab 真模型，blveh.json brdm2）。它是装甲侦察车、不是坦克（scout）：起步车照旧是 T-64A
      --   （用户 11-26「每个系从只给一辆最基础的坦克开始」——一挺 14.5 毫米机枪的侦察车打不动任何坦克，新玩家开它没法玩）。
      --   「自行防空」补 9K31 箭-1（2 级，blveh.json strela1），接在铠甲前面
      { "ru_brdm2", "BRDM-2", "BRDM-2", 1963, 1, 3, 5.7, veh = "brdm2", scout = true },
      { "ru_strela1", "9K31「箭-1」", "9K31 Strela-1", 1968, 2, 5, 7.0, veh = "strela1" },
      { "ru_pantsir", "铠甲-S1", "Pantsir-S1", 2012, 6, 5, 10.7, veh = "pantsir" },
    },
    [A] = {   -- 用户 11-26 给的原模型：米格-29、苏-25、苏-35S、T-50、苏-57（bohmerang / Immersive3A）；苏-27 系借苏-35S 的模型（原来借歼-11 的，机身上是中国机徽）
      { "ru_mig29", "米格-29（9.12）", "MiG-29 (9.12)", 1983, 4, 1, 12.0, veh = "mig29" },
      { "ru_su27", "苏-27", "Su-27", 1985, 4, 2, 12.7, veh = "su27" },
      { "ru_su27sm", "苏-27SM", "Su-27SM", 2004, 5, 2, 13.0, base = "su27" },
      { "ru_su30sm", "苏-30SM", "Su-30SM", 2012, 6, 2, 13.3, base = "j16" },
      { "ru_su35s", "苏-35S", "Su-35S", 2014, 6, 2, 13.7, veh = "su35" },
      { "ru_t50", "T-50（苏-57 原型机）", "T-50 (Su-57 prototype)", 2010, 7, 2, 14.0, veh = "t50" },
      { "ru_su57", "苏-57", "Su-57", 2020, 7, 2, 14.3, veh = "su57" },
      { "ru_su25", "苏-25「白嘴鸦」", "Su-25 Frogfoot", 1981, 3, 3, 10.3, veh = "su25" },
    },
    [H] = {   -- 俄罗斯：米-24、米-28N、卡-52（攻击）；米-8（运输）
      { "ru_mi24", "米-24V", "Mi-24V", 1976, 3, 1, 8.7, veh = "mi24" },
      { "ru_mi28", "米-28N", "Mi-28N", 2009, 6, 1, 10.3, veh = "mi28" },
      { "ru_ka52", "卡-52", "Ka-52", 2011, 6, 1, 10.7, veh = "ka52" },
      { "ru_mi8", "米-8MT", "Mi-8MT", 1967, 1, 2, 6.7, veh = "mi8" },
    },
  },
}

-- 起步车（用户 11-26：「不要一开始就给人解锁那么多坦克 就每个系从只给一辆最基础的坦克开始」）：每系每棵树只白送一辆，
--   按规则现算、不逐项写死（上面行里的 free = true 不再看）——以后加了更老的车，白送的自动换成它：
--   各列打头（没有前置）的车里，最低一级、年份最老的那一辆（再一样按战斗等级低的、列表里靠前的）；
--   地面树只在坦克那几列（主战、第二条线、轻型）里挑，一辆坦克都没有才看步战车、防空车；
--   轻型那一列里的侦察车（scout：BRDM-2、87 式侦察警戒车）不算坦克，不挑它；
--   直升机树、固定翼哪一列都行（11-26 纯运输直升机删了：起步的是最老、级别最低的那架——米-8MT、UH-1N、AH-1S、直-8、虎式）
local STARTER_COLS = { ground = { [1] = true, [2] = true, [3] = true } }
local function pickStarter(list, br)
  local pref = STARTER_COLS[br]
  for pass = 1, 2 do
    local best, bi
    for i, it in ipairs(list) do
      if it.prev == nil and (pass == 2 or not pref or (pref[it.col] and not it.scout)) then
        local better = not best
        if best then
          if it.rank ~= best.rank then better = it.rank < best.rank
          elseif (it.year or 0) ~= (best.year or 0) then better = (it.year or 0) < (best.year or 0)
          elseif it.br ~= best.br then better = it.br < best.br
          else better = i < bi end
        end
        if better then best, bi = it, i end
      end
    end
    if best or not pref then return best end
  end
  return nil
end
TT.pickStarter = pickStarter   -- 测试用：拿一份假的车单验证规则
TT.START = {}   -- [系][树] = 起步车的 key（这棵树空着就没有）

-- 展开：每项变成表，记前置（同一列的上一项）、研究点、价格
TT.byKey = {}
TT.list = {}   -- [系][树] = { 项, ... }（按列、按顺序）
for _, nat in ipairs(TT.NATIONS) do
  TT.START[nat] = {}
  TT.list[nat] = {}
  for _, br in ipairs(TT.BRANCHES) do
    local out, lastInCol = {}, {}
    for _, row in ipairs(LIST[nat][br]) do
      local it = { key = row[1], name = row[2], en = row[3], year = row[4], rank = row[5], col = row[6], br = row[7],
        veh = row.veh, base = row.base, model = row.model, scout = row.scout, nat = nat, branch = br }
      it.play = it.veh or it.base   -- 出车开哪一型
      it.stand = it.veh == nil      -- 暂用别的型号（模型和性能都借）
      -- model：性能是这一型自己的（VehDefs 里有它的炮、弹、装甲、机动），只是还没有它自己的模型，借同族那一型的真模型
      --   （用户 11-25「需要模型自己找」：T-80B 借 T-80U、豹 2A4 借 2A6、M60A1 借 M60A3 的模型；ImportedMeta 的 alias 把它指到那个模型）
      local prev = lastInCol[it.col]
      if prev and prev.rank > it.rank then prev = nil end   -- 写错顺序（上面比下面级别高）就不连
      it.prev = prev and prev.key or nil
      lastInCol[it.col] = it
      local R = TT.RANKS[it.rank]
      it.rp, it.cost = R.rp, R.cost
      it.free = false   -- 白送的只有起步车（下面按规则挑）
      table.insert(out, it)
      TT.byKey[it.key] = it
    end
    local st = pickStarter(out, br)
    if st then
      st.free = true
      TT.START[nat][br] = st.key
    end
    TT.list[nat][br] = out
  end
end

-- 型号 → 科技树里第一个用它自己性能的项（沙盒、电脑车没有 TreeKey：观瞄 WtOptics 按它查年代、国家）
TT.byVeh = {}
for _, nat in ipairs(TT.NATIONS) do
  for _, br in ipairs(TT.BRANCHES) do
    for _, it in ipairs(TT.list[nat][br]) do
      if it.veh and TT.byVeh[it.veh] == nil then TT.byVeh[it.veh] = it end
    end
  end
end

function TT.get(key) return TT.byKey[key] end
-- 这一系这棵树的起步车（白送的那一辆；树空着返回 nil）
function TT.starter(nat, br)
  local k = TT.START[nat] and TT.START[nat][br]
  return k and TT.byKey[k] or nil
end
-- 战斗等级的写法（10.0 → "10.0"）
function TT.brText(v) return string.format("%.1f", v or 0) end
-- 阵容的战斗等级：里面最高的那辆
function TT.lineupBr(keys)
  local m = 0
  for _, k in ipairs(keys or {}) do
    local it = TT.byKey[k]
    if it and it.br > m then m = it.br end
  end
  return m
end
-- 存档（每人）：res[key] = true 研究完、own[key] = true 买下、rp[key] = 攒了多少、cur[系 .. ":" .. 树] = 正在研究的 key
--   能不能研究这一辆：没研究完、前置研究完了、这一级开了（上一级研究完 RANK_NEED 辆）
function TT.rankOpen(save, nat, branch, rank)
  if rank <= 1 then return true end
  local B = TT.BRANCH[branch]
  local need = ((B and B.need) or TT.RANK_NEED)[rank - 1] or 2
  local n, cnt = 0, 0
  for _, it in ipairs(TT.list[nat][branch]) do
    if it.rank == rank - 1 then
      cnt += 1
      if (save.res or {})[it.key] or it.free then n += 1 end
    end
  end
  -- 上一级这棵树一辆都没有（直升机树车少，比如德国直接从五级的虎式开始）：再往上一级看，不把整棵树锁死；
  --   上一级只有一辆、要研究两辆的，研究完那一辆就算
  if cnt == 0 then return TT.rankOpen(save, nat, branch, rank - 1) end
  return n >= math.min(need, cnt)
end
-- 解锁这一级还差什么（界面上写，规则同 rankOpen）：返回 上一级研究完几辆、要几辆、看的是哪一级（上一级这棵树没车就再往上看）
function TT.rankNeed(save, nat, branch, rank)
  local B = TT.BRANCH[branch]
  for r = rank - 1, 1, -1 do
    local need = ((B and B.need) or TT.RANK_NEED)[r] or 2
    local n, cnt = 0, 0
    for _, it in ipairs(TT.list[nat][branch]) do
      if it.rank == r then
        cnt += 1
        if (save.res or {})[it.key] or it.free then n += 1 end
      end
    end
    if cnt > 0 then return n, math.min(need, cnt), r end
  end
  return 0, 0, 1
end
function TT.researched(save, key)
  local it = TT.byKey[key]
  return it ~= nil and (it.free or (save.res or {})[key] == true)
end
function TT.owned(save, key)
  local it = TT.byKey[key]
  return it ~= nil and (it.free or (save.own or {})[key] == true)
end
function TT.canResearch(save, key)
  local it = TT.byKey[key]
  if not it or TT.researched(save, key) then return false, "done" end
  if it.prev and not TT.researched(save, it.prev) then return false, "prev" end
  if not TT.rankOpen(save, it.nat, it.branch, it.rank) then return false, "rank" end
  return true
end

-- 真车的标准涂装（用户 11-25「很多车涂装纯米黄你给他改回原本颜色」）：还没有原模型、用零件拼的暂用车按这个上色，
--   不再按阵营一律刷沙色 / 林地绿。base 车体主色、dark 深色（迷彩深色块、阴影处）、light 浅色（迷彩浅色块、边角）；sRGB 0–255
--   解放军：早年 PLA 绿，2005 年以后的数码林地按绿褐近似；苏俄：4BO 绿，2010 年后偏卡其；
--   联邦国防军：1984 年以前 RAL 6014 黄橄榄，以后北约三色（RAL 6031 青铜绿 + 9021 焦油黑 + 8027 皮革棕）；
--   美军：1975 年以前 FS 34087 橄榄绿，1976–1990 MERDC / 北约林地三色，1991 年以后 CARC 686 沙色；陆上自卫队：橄榄绿 + 褐色两色
local PAINT = {
  cn = { { 2004, { 72, 86, 56 }, { 52, 62, 40 }, { 98, 108, 74 } }, { 9999, { 86, 96, 64 }, { 60, 58, 42 }, { 122, 120, 88 } } },
  ru = { { 2009, { 74, 88, 52 }, { 50, 60, 36 }, { 96, 108, 70 } }, { 9999, { 90, 92, 62 }, { 56, 58, 40 }, { 120, 118, 84 } } },
  de = { { 1983, { 92, 88, 62 }, { 64, 60, 42 }, { 118, 112, 82 } }, { 9999, { 64, 74, 58 }, { 36, 36, 34 }, { 82, 66, 50 } } },
  us = { { 1975, { 80, 84, 56 }, { 54, 58, 40 }, { 104, 104, 74 } }, { 1990, { 62, 72, 52 }, { 38, 38, 34 }, { 86, 72, 52 } },
    { 9999, { 176, 158, 116 }, { 128, 114, 84 }, { 198, 184, 146 } } },
  jp = { { 9999, { 82, 86, 60 }, { 80, 62, 46 }, { 106, 108, 80 } } },
}
function TT.paint(it)
  local list = it and PAINT[it.nat]
  if not list then return nil end
  for _, p in ipairs(list) do
    if (it.year or 0) <= p[1] then return { base = p[2], dark = p[3], light = p[4] } end
  end
  return nil
end

return TT
