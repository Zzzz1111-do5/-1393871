-- 全面大战场——坦克的观瞄按年代（用户 11-26「不同时期的坦克开镜不一样……以及夜视仪这种观瞄设备」）
--   客户端 Drive.lua 开镜时按它：能切哪几种光电通道、夜视是哪一种（画面不一样）、分划是哪一套
--   · 夜视（nv）：
--       ir  主动红外：车上的红外探照灯照出去、红外变像管看（六七十年代：T-55 / 59 式的 L-2「月亮」、M60 的 AN/VSS-1、豹 1 的 XSW-30）——
--           绿色、颗粒粗，只照得亮探照灯那一圈（几百米），外面一片黑
--       ii  微光夜视（像增强器）：不用灯，借星光放大（七十年代末到九十年代：T-72A 的 TPN-3、T-80U 的「布兰-PA」、96 式、RISE 型 M60A1）——
--           绿色、亮、颗粒细，亮的东西发晕
--       th1 第一代热像仪（M1 / M60A3 TTS 的 TIS、豹 2 的 WBG-X、99 式）：看热，白热 / 黑热；分辨率低、有扫描线、发糊
--       th2 第二代热像（SEP / SEPv2、T-90A 的「埃萨」、T-72B3 的「松树-U」、96A、99A）：清楚得多
--       th3 第三代高清热像（SEPv3、豹 2A7V、10 式、T-90M、96B）：最清楚，细节、远处都看得见
--       none 没有夜视（防空车的光学瞄准具）
--   · 分划（ret）按原厂火控是哪一代（WtMods.fcsGen：光学 → 光学测距 + 机械计算机 → 激光 + 模拟计算机 → 数字 → 猎歼）和东西方：
--       sov  苏式 TSh / TPD 分划：^ 形瞄准标、两边的提前量刻度、左边各弹种的表尺、左下按目标高 2.7 米的测距曲线（没有数字读数）
--       nato 北约早期弹道分划：细十字、往下一排各距离的落点横线（M60 的 M105D、豹 1 的 TZF 一类）
--       lrf  激光测距 + 模拟计算机：方框瞄准标、两边横线，下面激光测的距离（M1、豹 2A4、T-72A、T-80B 一类）
--       dig  数字火控：现在的分划（十字留空、圆点、弹种、距离、待发、状态一行）
--       hk   猎歼式：同数字火控，自动跟踪时框住目标
local O = {}

O.NV = {
  none = { zh = "无夜视", en = "No night sight" },
  ir = { zh = "主动红外夜视", en = "Active IR", short = { "主动红外", "ACTIVE IR" } },
  ii = { zh = "微光夜视（像增强器）", en = "Image intensifier", short = { "微光夜视", "II NIGHT" } },
  th1 = { zh = "第一代热像仪", en = "Gen-1 thermal", short = { "热像 1 代", "TI GEN 1" }, blur = 3, lines = true, gain = -0.12 },
  th2 = { zh = "第二代热像仪", en = "Gen-2 thermal", short = { "热像 2 代", "TI GEN 2" }, blur = 1.2, lines = false, gain = 0 },
  th3 = { zh = "第三代高清热像仪", en = "Gen-3 HD thermal", short = { "热像 3 代", "TI GEN 3" }, blur = 0, lines = false, gain = 0.06 },
}
O.RET = {
  sov = { zh = "苏式光学分划（测距曲线 + 表尺）", en = "Soviet optical reticle (stadia + range scales)" },
  nato = { zh = "早期弹道分划（落点刻线）", en = "Early ballistic reticle (range drop lines)" },
  lrf = { zh = "激光测距分划（方框瞄准标）", en = "Laser rangefinder reticle (box)" },
  dig = { zh = "数字火控分划", en = "Digital FCS reticle" },
  hk = { zh = "猎歼式数字分划（自动跟踪）", en = "Hunter-killer digital reticle (auto-track)" },
}

-- 每辆车真车的夜视（科技树的键；查的公开资料）：没写的按年份、东西方推（O.nvByYear）
O.TREE_NV = {
  cn_59 = "ir", cn_69 = "ir", cn_86 = "ir", cn_96 = "ii", cn_96a = "th2", cn_96b = "th3", cn_99 = "th1", cn_99a = "th2", cn_pgl625 = "th3",
  de_leo1 = "ir", de_leo1a1a1 = "ii", de_leo1a5 = "th1", de_leo2a0 = "ii", de_leo2a4 = "th1", de_leo2a5 = "th1", de_leo2a6 = "th2", de_leo2a7v = "th3",
  de_gepard = "none", de_gepard1a2 = "none",
  us_m60 = "ir", us_m60a1 = "ir", us_m60a1rise = "ii", us_m60a3 = "th1", us_m1 = "th1", us_m1ip = "th1", us_m1a1 = "th1", us_m1a1hc = "th1",
  us_m1a2 = "th1", us_m1a2sep = "th2", us_m1a2sep2 = "th2", us_m1a2sep3 = "th3", us_m551 = "ir", us_m2 = "th1", us_m2a2 = "th1", us_m2a3 = "th2",
  us_m163 = "none",
  jp_type74 = "ir", jp_type74g = "ii", jp_type10 = "th3",
  ru_t72 = "ir", ru_t72a = "ii", ru_t72b = "ii", ru_t90a = "th2", ru_t72b3 = "th2", ru_t90m = "th3", ru_t64a = "ir", ru_t64b = "ii", ru_t80b = "ii",
  ru_t80u = "ii", ru_t80bvm = "th2", ru_bmp1 = "ir", ru_bmp2 = "ir", ru_bmp2m = "th2", ru_pantsir = "th2",
  -- 11-27 补的：BRDM-2 炮手的 PP-61AM、箭-1 的光学瞄准具都没有夜视；87 式炮长瞄准镜带微光夜视
  ru_brdm2 = "none", ru_strela1 = "none", jp_type87rcv = "ii",
}
-- 没走科技树的车（沙盒、电脑车）按型号
O.VEH_NV = {
  type59 = "ir", type69 = "ir", m60a1 = "ir", m551 = "ir", leo1 = "ir", type74 = "ir", t64a = "ir", t72ural = "ir", bmp1 = "ir", bmp2 = "ir",
  t72a = "ii", t64b = "ii", t80b = "ii", t72b = "ii", t80u = "ii", ztz96 = "ii", type74g = "ii",
  m60a3 = "th1", leo1a5 = "th1", leo2a4 = "th1", m1a1 = "th1", ztz99a = "th2", m1a2 = "th2", leo2a6 = "th2", t72b3 = "th2", bmp2m = "th2",
  t80bvm = "th2", m2a3 = "th2", leo2a7v = "th3", type10 = "th3", t90m = "th3", leclerc = "th2",
  brdm2 = "none", strela1 = "none", type87rcv = "ii",
  -- 11-27 拆开重叠的版本：同族的老 / 新型号各自的夜视（同 TREE_NV）
  m1 = "th1", m1ip = "th1", m1a1hc = "th1", m1a2base = "th1", m1a2sep = "th2", m1a2sep3 = "th3",
}
local EAST = { cn = true, ru = true }
function O.nvByYear(year, nat)
  local y = year or 2000
  local east = EAST[nat or ""] == true
  if y < 1975 then return "ir" end
  if east then
    if y < 2000 then return (y < 1977) and "ir" or "ii" end
    if y < 2016 then return "th2" end
    return "th3"
  end
  if y < 1979 then return "ii" end
  if y < 2000 then return "th1" end
  if y < 2015 then return "th2" end
  return "th3"
end

-- 这辆车的观瞄：treeKey 科技树的键（可空）、vid 型号、fcsGen 原厂火控代（WtMods.fcsGen，可空）、year / nat（可空：从科技树查）
--   返回 { nv = 夜视, ret = 分划, modes = { 能切的光电通道编号… }（1 昼光、2 微光、3 白热、4 黑热、5 主动红外）, east = 东方 }
function O.kit(treeKey, vid, fcsGen, year, nat)
  local nv = (treeKey and O.TREE_NV[treeKey]) or (vid and O.VEH_NV[vid]) or O.nvByYear(year, nat)
  local east = EAST[nat or ""] == true
  if nat == nil and treeKey then east = (string.sub(treeKey, 1, 3) == "cn_") or (string.sub(treeKey, 1, 3) == "ru_") end
  local g = fcsGen
  if g == nil then
    local y = year or 2000
    g = (y < 1965 and 0) or (y < 1978 and 1) or (y < 1992 and 2) or (y < 2006 and 3) or 4
  end
  local ret = (g <= 1) and (east and "sov" or "nato") or ((g == 2) and "lrf" or ((g >= 4) and "hk" or "dig"))
  local modes = { 1 }
  if nv == "ir" then table.insert(modes, 5)
  elseif nv == "ii" then table.insert(modes, 2)
  elseif nv == "th1" or nv == "th2" or nv == "th3" then table.insert(modes, 3) table.insert(modes, 4) end
  return { nv = nv, ret = ret, modes = modes, east = east, gen = g }
end

return O
