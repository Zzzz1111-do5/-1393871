-- 全面大战场（共用）——科技树（用户 11-25：「从1960到现代的战机和坦克 科技树」「再去做一个中 德 美 日 俄系」，发了战雷科技树的截图）
--   五个系（中、德、美、日、俄）× 两棵树（地面：坦克等；空中：喷气式战机），按年代分七级、每级一行，按车种分列，同一列上下连线（前置）。
--   玩法照战雷那一套（我们自己的数、自己的界面，不照搬名字和美术）：
--   · 研究：打仗挣研究点，记在「正在研究」的那一辆上，攒够这一辆的研究点就研究完；一级里研究完 RANK_NEED 辆才能研究下一级
--   · 购买：研究完以后花金币买下；买下的才能放进出击阵容
--   · 战斗等级 br（0.3 / 0.4 一档）：阵容的战斗等级 = 里面最高的那辆；分房按 ±1.0
--   · 每系每棵树第一级各列打头的那一辆白送（研究完、买好）
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
TT.BRANCHES = { "ground", "air" }
TT.BRANCH = {
  ground = { name = "坦克", en = "Ground", cols = { { "主战坦克", "MBT" }, { "主战坦克 · 第二条线", "MBT II" }, { "轻型 / 歼击车", "Light / TD" },
    { "步兵战车", "IFV" }, { "自行防空", "SPAA" } } },
  air = { name = "战机", en = "Aircraft", cols = { { "战斗机", "Fighters" }, { "重型 / 多用途", "Heavy / Multirole" }, { "攻击机 / 轰炸机", "Strike" } } },
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
local G, A = "ground", "air"
local LIST = {
  cn = {
    [G] = {
      { "cn_59", "59式中型坦克", "Type 59", 1959, 1, 1, 6.0, base = "m60a1" },
      { "cn_69", "69式中型坦克", "Type 69", 1974, 2, 1, 7.0, base = "m60a1" },
      { "cn_79", "79式中型坦克", "Type 79", 1984, 3, 1, 7.7, base = "m60a3" },
      { "cn_88b", "88B式主战坦克", "Type 88B", 1995, 4, 1, 8.7, base = "m60a3" },
      { "cn_96", "96式主战坦克", "Type 96", 1997, 5, 1, 9.7, base = "ztz96" },
      { "cn_96a", "96A式主战坦克", "Type 96A", 2006, 6, 1, 10.3, base = "ztz96" },
      { "cn_96b", "96B式主战坦克", "Type 96B", 2016, 7, 1, 10.7, veh = "ztz96" },
      { "cn_80", "80式主战坦克", "Type 80", 1985, 3, 2, 8.0, base = "ztz96" },
      { "cn_85iim", "85-IIM式主战坦克", "Type 85-IIM", 1992, 4, 2, 9.0, base = "ztz96" },
      { "cn_99", "99式主战坦克", "Type 99", 2001, 5, 2, 10.7, base = "ztz99a" },
      { "cn_99a", "99A式主战坦克", "Type 99A", 2011, 6, 2, 11.7, veh = "ztz99a" },
      { "cn_62", "62式轻型坦克", "Type 62", 1963, 1, 3, 5.7, base = "leo1" },
      { "cn_63", "63式水陆坦克", "Type 63", 1963, 1, 3, 5.3, base = "bmp1" },
      { "cn_ptz89", "89式反坦克炮", "PTZ-89", 1990, 4, 3, 8.3, base = "m60a3" },
      { "cn_ptl02", "PTL-02 突击炮", "PTL-02", 2002, 5, 3, 9.0, base = "leo1a5" },
      { "cn_ztd05", "05式两栖突击车", "ZTD-05", 2006, 6, 3, 9.7, base = "leo1a5" },
      { "cn_15", "15式轻型坦克", "Type 15", 2018, 7, 3, 10.3, base = "leo1a5" },
      { "cn_yw531", "63式装甲运输车", "YW531", 1963, 1, 4, 5.0, base = "m2a3" },
      { "cn_86", "86式步兵战车", "Type 86", 1986, 4, 4, 7.7, base = "bmp1" },
      { "cn_zsl92b", "92B式轮式步兵战车", "ZSL-92B", 2000, 5, 4, 8.3, base = "m2a3" },
      { "cn_zbd04", "04式步兵战车", "ZBD-04", 2004, 5, 4, 9.0, base = "bmp1" },
      { "cn_zbd05", "05式两栖步兵战车", "ZBD-05", 2006, 6, 4, 9.7, base = "bmp1" },
      { "cn_zbd04a", "04A式步兵战车", "ZBD-04A", 2011, 6, 4, 10.0, base = "bmp1" },
      { "cn_80aa", "80式双57毫米自行高炮", "Type 80 SPAAG", 1980, 3, 5, 7.0, base = "m163" },
      { "cn_pgz88", "PGZ-88 自行高炮", "PGZ-88", 1988, 4, 5, 8.0, base = "pgz07" },
      { "cn_pgz95", "PGZ-95 自行高炮", "PGZ-95", 1999, 5, 5, 9.0, base = "pgz07" },
      { "cn_pgz07", "PGZ-07 自行高炮", "PGZ-07", 2007, 6, 5, 10.0, veh = "pgz07" },
      { "cn_ld2000", "LD-2000 近防系统", "LD-2000", 2005, 6, 5, 10.3, veh = "ld2000" },
      { "cn_pgl625", "PGL-625 自行高炮", "PGL-625", 2019, 7, 5, 11.0, veh = "pgl625" },
    },
    [A] = {
      { "cn_j6", "歼-6", "J-6", 1962, 1, 1, 8.0, base = "j8" },
      { "cn_j7", "歼-7", "J-7", 1966, 1, 1, 8.7, base = "j10" },
      { "cn_j7ii", "歼-7II", "J-7II", 1979, 3, 1, 9.3, base = "j10" },
      { "cn_j7e", "歼-7E", "J-7E", 1993, 5, 1, 10.0, base = "j10" },
      { "cn_j10a", "歼-10A", "J-10A", 2004, 5, 1, 12.0, base = "j10" },
      { "cn_j10c", "歼-10C", "J-10C", 2018, 7, 1, 13.3, veh = "j10" },
      { "cn_j8", "歼-8", "J-8", 1980, 3, 2, 9.7, base = "j8" },
      { "cn_j8ii", "歼-8II", "J-8II", 1988, 4, 2, 10.7, veh = "j8" },
      { "cn_j11", "歼-11", "J-11", 1998, 5, 2, 12.3, base = "j11" },
      { "cn_j11b", "歼-11B", "J-11B", 2007, 6, 2, 12.7, veh = "j11" },
      { "cn_j16", "歼-16", "J-16", 2015, 6, 2, 13.3, veh = "j16" },
      { "cn_j15t", "歼-15T", "J-15T", 2019, 7, 2, 13.7, veh = "j15t" },
      { "cn_j20", "歼-20", "J-20", 2017, 7, 2, 14.0, veh = "j20" },
      { "cn_j35", "歼-35", "J-35", 2025, 7, 2, 14.0, veh = "j35" },
      { "cn_q5", "强-5", "Q-5", 1970, 2, 3, 8.7, base = "a10c" },
      { "cn_q5c", "强-5C", "Q-5C", 1983, 3, 3, 9.3, base = "a10c" },
      { "cn_jh7", "歼轰-7", "JH-7", 1992, 5, 3, 11.0, base = "f15" },
      { "cn_jh7a", "歼轰-7A", "JH-7A", 2004, 5, 3, 11.7, base = "f15" },
      { "cn_h6k", "轰-6K", "H-6K", 2011, 6, 3, 11.0, veh = "h6k" },
      { "cn_gj11", "攻击-11", "GJ-11", 2019, 7, 3, 12.0, veh = "gj11" },
    },
  },
  de = {
    [G] = {
      { "de_leo1", "豹1", "Leopard 1", 1965, 1, 1, 7.0, veh = "leo1" },
      { "de_leo1a1a1", "豹1A1A1", "Leopard 1A1A1", 1975, 2, 1, 7.7, base = "leo1" },
      { "de_leo1a5", "豹1A5", "Leopard 1A5", 1987, 4, 1, 8.3, veh = "leo1a5", model = "leo1" },
      { "de_leo2a0", "豹2A0", "Leopard 2A0", 1979, 3, 2, 9.0, base = "leo2a4" },
      { "de_leo2a4", "豹2A4", "Leopard 2A4", 1985, 4, 2, 9.7, veh = "leo2a4", model = "leo2a6" },
      { "de_leo2a5", "豹2A5", "Leopard 2A5", 1995, 5, 2, 10.7, base = "leo2a6" },
      { "de_leo2a6", "豹2A6", "Leopard 2A6", 2001, 5, 2, 11.3, veh = "leo2a6" },
      { "de_leo2a7v", "豹2A7V", "Leopard 2A7V", 2020, 7, 2, 12.0, veh = "leo2a7v" },
      { "de_kanjpz", "90毫米炮歼击车", "Kanonenjagdpanzer", 1965, 1, 3, 6.3, base = "leo1" },
      { "de_jaguar1", "美洲虎1 反坦克导弹车", "Jaguar 1", 1978, 3, 3, 8.3, base = "m2a3" },
      { "de_wiesel", "鼬鼠1 陶式", "Wiesel 1A2", 1990, 4, 3, 8.7, base = "m2a3" },
      { "de_hs30", "HS.30 步兵战车", "Schützenpanzer HS.30", 1960, 1, 4, 5.0, base = "m2a3" },
      { "de_marder1a1", "黄鼠狼1A1", "Marder 1A1", 1971, 2, 4, 7.0, base = "m2a3" },
      { "de_marder1a3", "黄鼠狼1A3", "Marder 1A3", 1979, 3, 4, 7.7, base = "m2a3" },
      { "de_puma", "美洲狮", "Puma", 2015, 6, 4, 10.0, base = "m2a3" },
      { "de_m42", "M42 双40毫米自行高炮", "M42 Duster", 1960, 1, 5, 5.7, base = "m163" },
      { "de_gepard", "猎豹1A1", "Gepard 1A1", 1976, 3, 5, 8.3, base = "pgz07" },
      { "de_gepard1a2", "猎豹1A2", "Gepard 1A2", 1998, 5, 5, 9.3, base = "pgz07" },
      { "de_ozelot", "豹猫 防空导弹车", "Ozelot", 2001, 5, 5, 9.7, base = "mshorad" },
      { "de_skyranger", "天空游侠30", "Skyranger 30", 2024, 7, 5, 11.0, base = "mshorad" },
    },
    [A] = {
      { "de_f104g", "F-104G 星式", "F-104G", 1960, 1, 1, 9.0, base = "f16" },
      { "de_f4f", "F-4F 鬼怪II", "F-4F", 1973, 2, 1, 10.7, base = "f15" },
      { "de_mig29g", "米格-29G", "MiG-29G", 1991, 4, 1, 12.0, base = "j11" },
      { "de_f4fice", "F-4F ICE", "F-4F ICE", 1992, 4, 1, 11.7, base = "f15" },
      { "de_ef2000", "台风 EF2000", "Typhoon EF2000", 2003, 5, 1, 13.0, base = "j10" },
      { "de_ef2000t3", "台风 T3", "Typhoon Tranche 3", 2015, 6, 1, 13.7, base = "j10" },
      { "de_g91", "G.91R/3", "G.91 R/3", 1961, 1, 3, 8.7, base = "a10c" },
      { "de_alphajet", "阿尔法喷气", "Alpha Jet A", 1979, 3, 3, 9.0, base = "a10c" },
      { "de_tornado", "狂风 IDS", "Tornado IDS", 1981, 3, 3, 11.0, base = "f14" },
      { "de_tornadoecr", "狂风 ECR", "Tornado ECR", 1990, 4, 3, 11.7, base = "f14" },
      { "de_tornado3", "狂风 IDS ASSTA3", "Tornado IDS ASSTA3", 2014, 6, 3, 12.3, base = "f14" },
    },
  },
  us = {
    [G] = {
      { "us_m60", "M60 巴顿", "M60", 1960, 1, 1, 7.0, base = "m60a1" },
      { "us_m60a1", "M60A1", "M60A1", 1962, 1, 1, 7.3, veh = "m60a1", model = "m60a3" },
      { "us_m60a1rise", "M60A1 RISE", "M60A1 RISE", 1977, 3, 1, 7.7, base = "m60a1" },
      { "us_m60a3", "M60A3 TTS", "M60A3 TTS", 1979, 3, 1, 8.0, veh = "m60a3" },
      { "us_m1", "M1 艾布拉姆斯", "M1 Abrams", 1980, 3, 2, 9.3, base = "m1a1" },
      { "us_m1ip", "M1IP", "IPM1", 1984, 4, 2, 9.7, base = "m1a1" },
      { "us_m1a1", "M1A1", "M1A1", 1985, 4, 2, 10.3, veh = "m1a1" },
      { "us_m1a1hc", "M1A1 HC", "M1A1 HC", 1988, 4, 2, 10.7, base = "m1a1" },
      { "us_m1a2", "M1A2", "M1A2", 1992, 5, 2, 11.0, base = "m1a2" },
      { "us_m1a2sep", "M1A2 SEP", "M1A2 SEP", 2000, 5, 2, 11.3, base = "m1a2" },
      { "us_m1a2sep2", "M1A2 SEPv2", "M1A2 SEPv2", 2008, 6, 2, 11.7, veh = "m1a2" },
      { "us_m1a2sep3", "M1A2 SEPv3", "M1A2 SEPv3", 2017, 7, 2, 12.0, base = "m1a2" },
      { "us_m551", "M551 谢里登", "M551 Sheridan", 1966, 1, 3, 6.3, veh = "m551" },
      { "us_m901", "M901 陶式导弹车", "M901 ITV", 1979, 3, 3, 7.7, base = "m2a3" },
      { "us_m1128", "M1128 斯特赖克机动炮", "M1128 MGS", 2002, 5, 3, 9.3, base = "leo1a5" },
      { "us_m10", "M10 布克", "M10 Booker", 2023, 7, 3, 10.0, base = "leo1a5" },
      { "us_m113", "M113A1 装甲运输车", "M113A1", 1964, 1, 4, 5.0, base = "m2a3" },
      { "us_m2", "M2 布雷德利", "M2 Bradley", 1981, 3, 4, 8.0, base = "m2a3" },
      { "us_m2a2", "M2A2 布雷德利", "M2A2", 1988, 4, 4, 8.7, base = "m2a3" },
      { "us_m2a3", "M2A3 布雷德利", "M2A3", 2000, 5, 4, 9.3, veh = "m2a3" },
      { "us_stryker", "M1126 斯特赖克", "M1126 Stryker", 2002, 5, 4, 9.0, base = "m2a3" },
      { "us_m1150", "M1150 突击破障车", "M1150 ABV", 2008, 6, 4, 9.7, base = "m2a3" },
      { "us_m42", "M42 掸子", "M42 Duster", 1960, 1, 5, 5.7, base = "m163" },
      { "us_m163", "M163 火神", "M163 VADS", 1968, 2, 5, 7.0, veh = "m163" },
      { "us_avenger", "M1097 复仇者", "M1097 Avenger", 1990, 4, 5, 8.7, base = "mshorad" },
      { "us_m6", "M6 后卫", "M6 Linebacker", 1997, 5, 5, 9.3, base = "mshorad" },
      { "us_cram", "C-RAM 陆基密集阵", "C-RAM", 2005, 6, 5, 10.0, veh = "cram" },
      { "us_patriot", "爱国者", "Patriot", 2010, 6, 5, 11.3, veh = "patriot" },
      { "us_mshorad", "M-SHORAD", "M-SHORAD", 2020, 7, 5, 11.0, veh = "mshorad" },
    },
    [A] = {
      { "us_f8e", "F-8E 十字军", "F-8E Crusader", 1962, 1, 1, 9.3, base = "f16" },
      { "us_f5e", "F-5E 虎II", "F-5E Tiger II", 1972, 2, 1, 10.3, base = "f16" },
      { "us_f16a", "F-16A 战隼", "F-16A", 1978, 3, 1, 12.0, base = "f16" },
      { "us_f16c", "F-16C 战隼", "F-16C", 1984, 4, 1, 13.0, veh = "f16" },
      { "us_fa18c", "F/A-18C 大黄蜂", "F/A-18C Hornet", 1987, 4, 1, 12.7, base = "f15" },
      { "us_f35a", "F-35A 闪电II", "F-35A", 2016, 7, 1, 14.0, veh = "f35" },
      { "us_f4c", "F-4C 鬼怪II", "F-4C Phantom II", 1963, 1, 2, 9.7, base = "f15" },
      { "us_f4e", "F-4E 鬼怪II", "F-4E Phantom II", 1967, 2, 2, 10.7, base = "f15" },
      { "us_f14a", "F-14A 雄猫", "F-14A Tomcat", 1974, 2, 2, 12.0, veh = "f14" },
      { "us_f15a", "F-15A 鹰", "F-15A Eagle", 1976, 3, 2, 12.3, base = "f15" },
      { "us_f15c", "F-15C 鹰", "F-15C Eagle", 1979, 3, 2, 12.7, veh = "f15" },
      { "us_f15e", "F-15E 攻击鹰", "F-15E Strike Eagle", 1988, 4, 2, 13.3, base = "f15" },
      { "us_f22a", "F-22A 猛禽", "F-22A Raptor", 2005, 5, 2, 14.0, veh = "f22" },
      { "us_a4e", "A-4E 天鹰", "A-4E Skyhawk", 1962, 1, 3, 8.7, base = "a10c" },
      { "us_a7d", "A-7D 海盗II", "A-7D Corsair II", 1970, 2, 3, 9.3, base = "a10c" },
      { "us_f111f", "F-111F 土豚", "F-111F Aardvark", 1971, 2, 3, 10.3, base = "f14" },
      { "us_a10a", "A-10A 雷电II", "A-10A Thunderbolt II", 1977, 3, 3, 10.7, base = "a10c" },
      { "us_b2", "B-2 幽灵", "B-2 Spirit", 1997, 5, 3, 12.0, veh = "b2" },
      { "us_a10c", "A-10C 雷电II", "A-10C Thunderbolt II", 2007, 6, 3, 11.3, veh = "a10c" },
      { "us_mq9", "MQ-9 死神", "MQ-9 Reaper", 2007, 6, 3, 11.0, veh = "mq9" },
    },
  },
  jp = {
    [G] = {
      { "jp_type61", "61式主战坦克", "Type 61", 1961, 1, 1, 6.7, base = "leo1" },
      { "jp_type74", "74式主战坦克", "Type 74", 1975, 2, 1, 8.0, base = "leo1" },
      { "jp_type74g", "74式改", "Type 74 (G)", 1993, 4, 1, 8.7, base = "leo1a5" },
      { "jp_type90", "90式主战坦克", "Type 90", 1990, 4, 2, 10.3, base = "m1a1" },
      { "jp_type90b", "90式（B）", "Type 90 (B)", 1999, 5, 2, 10.7, base = "m1a1" },
      { "jp_type10", "10式主战坦克", "Type 10", 2012, 6, 2, 11.3, veh = "type10" },
      { "jp_type60", "60式自行无后坐力炮", "Type 60 SPRG", 1960, 1, 3, 5.3, base = "leo1" },
      { "jp_type87rcv", "87式侦察警戒车", "Type 87 RCV", 1987, 4, 3, 7.3, base = "m2a3" },
      { "jp_type16", "16式机动战斗车", "Type 16 MCV", 2016, 7, 3, 9.7, base = "leo1a5" },
      { "jp_type73", "73式装甲运输车", "Type 73 APC", 1973, 2, 4, 6.0, base = "m2a3" },
      { "jp_type89", "89式步兵战车", "Type 89 IFV", 1989, 4, 4, 8.7, base = "m2a3" },
      { "jp_type96", "96式轮式装甲车", "Type 96 WAPC", 1996, 5, 4, 8.0, base = "m2a3" },
      { "jp_m42", "M42 自行高炮", "M42 Duster", 1960, 1, 5, 5.7, base = "m163" },
      { "jp_type87aa", "87式自行高炮", "Type 87 SPAAG", 1987, 4, 5, 8.7, base = "pgz07" },
      { "jp_type93", "93式近程防空导弹", "Type 93 SAM", 1993, 5, 5, 9.3, base = "mshorad" },
    },
    [A] = {
      { "jp_f86f", "F-86F 佩刀", "F-86F Sabre", 1955, 1, 1, 7.7, base = "f16" },
      { "jp_f104j", "F-104J 荣光", "F-104J", 1962, 1, 1, 9.0, base = "f16" },
      { "jp_f4ej", "F-4EJ 鬼怪II", "F-4EJ", 1971, 2, 1, 10.7, base = "f15" },
      { "jp_f15j", "F-15J 鹰", "F-15J", 1981, 3, 1, 12.3, veh = "f15" },
      { "jp_f4ejkai", "F-4EJ 改", "F-4EJ Kai", 1989, 4, 1, 11.3, base = "f15" },
      { "jp_f15jm", "F-15J（M）", "F-15J (M)", 2007, 6, 1, 13.0, base = "f15" },
      { "jp_f35a", "F-35A 闪电II", "F-35A", 2018, 7, 1, 14.0, veh = "f35" },
      { "jp_t2", "T-2", "T-2", 1975, 2, 3, 9.3, base = "f16" },
      { "jp_f1", "F-1", "F-1", 1977, 3, 3, 9.7, base = "f16" },
      { "jp_f2a", "F-2A", "F-2A", 2000, 5, 3, 12.3, base = "f16" },
    },
  },
  ru = {
    [G] = {
      { "ru_t55a", "T-55A", "T-55A", 1963, 1, 1, 7.0, base = "m60a1" },
      { "ru_t62", "T-62", "T-62", 1961, 1, 1, 7.3, base = "m60a1" },
      { "ru_t72", "T-72 乌拉尔", "T-72 Ural", 1973, 2, 1, 8.0, veh = "t72ural", model = "t72b3" },
      { "ru_t72a", "T-72A", "T-72A", 1979, 3, 1, 8.7, veh = "t72a", model = "t72b3" },
      { "ru_t72b", "T-72B", "T-72B", 1985, 4, 1, 9.7, veh = "t72b", model = "t72b3" },
      { "ru_t90a", "T-90A", "T-90A", 2004, 5, 1, 10.7, base = "t90m" },
      { "ru_t72b3", "T-72B3", "T-72B3", 2013, 6, 1, 11.0, veh = "t72b3" },
      { "ru_t90m", "T-90M 突破-3", "T-90M", 2020, 7, 1, 12.0, veh = "t90m" },
      { "ru_t64a", "T-64A", "T-64A", 1969, 2, 2, 8.3, base = "t80b" },
      { "ru_t64b", "T-64B", "T-64B", 1976, 3, 2, 9.3, base = "t80b" },
      { "ru_t80b", "T-80B", "T-80B", 1978, 3, 2, 9.7, veh = "t80b", model = "t80u" },
      { "ru_t80u", "T-80U", "T-80U", 1985, 4, 2, 10.7, veh = "t80u" },
      { "ru_t80bvm", "T-80BVM", "T-80BVM", 2018, 7, 2, 11.7, veh = "t80bvm", model = "t80u" },
      { "ru_pt76b", "PT-76B 水陆坦克", "PT-76B", 1962, 1, 3, 5.7, base = "bmp1" },
      { "ru_shturm", "强袭-S 反坦克导弹车", "Shturm-S", 1979, 3, 3, 8.3, base = "m2a3" },
      { "ru_khriz", "菊花-S 反坦克导弹车", "Khrizantema-S", 2005, 5, 3, 10.0, base = "m2a3" },
      { "ru_bmp1", "BMP-1", "BMP-1", 1966, 1, 4, 6.7, veh = "bmp1" },
      { "ru_bmp2", "BMP-2", "BMP-2", 1980, 3, 4, 7.7, base = "bmp1" },
      { "ru_bmp3", "BMP-3", "BMP-3", 1987, 4, 4, 8.7, base = "bmp1" },
      { "ru_bmp2m", "BMP-2M", "BMP-2M", 2000, 5, 4, 9.3, base = "bmp1" },
      { "ru_bmpt", "BMPT 终结者", "BMPT Terminator", 2011, 6, 4, 10.0, base = "t90m" },
      { "ru_zsu234", "ZSU-23-4 石勒喀", "ZSU-23-4 Shilka", 1965, 1, 5, 7.0, base = "pgz07" },
      { "ru_2s6", "2S6 通古斯卡", "2S6 Tunguska", 1982, 3, 5, 9.0, base = "pantsir" },
      { "ru_2s6m1", "2S6M1 通古斯卡", "2S6M1", 2003, 5, 5, 10.0, base = "pantsir" },
      { "ru_pantsir", "铠甲-S1", "Pantsir-S1", 2012, 6, 5, 10.7, veh = "pantsir" },
      { "ru_torm2", "道尔-M2", "Tor-M2", 2016, 7, 5, 11.3, base = "pantsir" },
    },
    [A] = {
      { "ru_mig21f13", "米格-21F-13", "MiG-21F-13", 1960, 1, 1, 8.7, base = "j10" },
      { "ru_mig21pfm", "米格-21PFM", "MiG-21PFM", 1964, 1, 1, 9.3, base = "j10" },
      { "ru_mig21bis", "米格-21bis", "MiG-21bis", 1972, 2, 1, 10.3, base = "j10" },
      { "ru_mig23mld", "米格-23MLD", "MiG-23MLD", 1982, 3, 1, 11.3, base = "f14" },
      { "ru_mig29", "米格-29", "MiG-29", 1983, 3, 1, 12.0, base = "j11" },
      { "ru_mig29smt", "米格-29SMT", "MiG-29SMT", 2004, 5, 1, 12.7, base = "j11" },
      { "ru_su57", "苏-57", "Su-57", 2020, 7, 1, 14.0, base = "j20" },
      { "ru_mig25pd", "米格-25PD", "MiG-25PD", 1979, 3, 2, 11.0, base = "f15" },
      { "ru_mig31", "米格-31", "MiG-31", 1981, 3, 2, 11.7, base = "f15" },
      { "ru_su27", "苏-27", "Su-27", 1985, 4, 2, 12.7, base = "j11" },
      { "ru_su27sm", "苏-27SM", "Su-27SM", 2004, 5, 2, 13.0, base = "j11" },
      { "ru_su30sm", "苏-30SM", "Su-30SM", 2012, 6, 2, 13.3, base = "j16" },
      { "ru_su35s", "苏-35S", "Su-35S", 2014, 6, 2, 13.7, base = "j11" },
      { "ru_su7bkl", "苏-7BKL", "Su-7BKL", 1961, 1, 3, 8.3, base = "a10c" },
      { "ru_su17m2", "苏-17M2", "Su-17M2", 1974, 2, 3, 9.7, base = "f14" },
      { "ru_mig27k", "米格-27K", "MiG-27K", 1975, 2, 3, 10.0, base = "f14" },
      { "ru_su25", "苏-25", "Su-25", 1981, 3, 3, 10.3, base = "a10c" },
      { "ru_su24m", "苏-24M", "Su-24M", 1983, 3, 3, 11.0, base = "f14" },
      { "ru_su25sm", "苏-25SM", "Su-25SM", 2003, 5, 3, 11.3, base = "a10c" },
      { "ru_su34", "苏-34", "Su-34", 2014, 6, 3, 12.3, base = "j11" },
    },
  },
}

-- 展开：每项变成表，记前置（同一列的上一项）、研究点、价格
TT.byKey = {}
TT.list = {}   -- [系][树] = { 项, ... }（按列、按顺序）
for _, nat in ipairs(TT.NATIONS) do
  TT.list[nat] = {}
  for _, br in ipairs(TT.BRANCHES) do
    local out, lastInCol = {}, {}
    for _, row in ipairs(LIST[nat][br]) do
      local it = { key = row[1], name = row[2], en = row[3], year = row[4], rank = row[5], col = row[6], br = row[7],
        veh = row.veh, base = row.base, model = row.model, nat = nat, branch = br }
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
      it.free = it.rank == 1 and it.prev == nil   -- 第一级各列打头的白送
      table.insert(out, it)
      TT.byKey[it.key] = it
    end
    TT.list[nat][br] = out
  end
end

function TT.get(key) return TT.byKey[key] end
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
  local need = TT.RANK_NEED[rank - 1] or 2
  local n = 0
  for _, it in ipairs(TT.list[nat][branch]) do
    if it.rank == rank - 1 and ((save.res or {})[it.key] or it.free) then n += 1 end
  end
  return n >= need
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
