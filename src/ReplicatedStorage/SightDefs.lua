-- 全面大战场（共用）——坦克炮长瞄准镜、车长望远镜的分划（用户 11-27：「坦克的开镜你直接去按照战雷的做」，发了一张截图「这个样子」，
--   「然后再做一个望远镜」；11-26 看了旧的红色分划嫌难看：「照真镜子重画：白天黑色细线、上方各弹种距离表尺 + 指示线、两边每格 4 密位、
--   左下 2.7 米测距曲线、按密位随倍率缩放」）。客户端 GunSight.lua 照这里画；这里只有数和算法（纯 Lua，模拟测试直接 require）。
--   · 全屏：不再套圆形目镜 / 热像的方框，画面铺满，分划是细线（白天黑色；黑热、夜视黑色；白热亮色；夜里白天通道开分划照明是暗红）
--   · 尺寸都按密位：一圈分成 6000（苏联、中国：「千分之一」≈ 1.047 毫弧度）或 6400（北约、日本 ≈ 0.982 毫弧度）；
--     屏幕上一密位多少像素按镜头视场算（GunSight），换倍率整套分划跟着放大缩小（真镜子是第一焦平面那样）
--   · 表尺（下坠刻度，截图里竖线左边那一列 4 8 12 …）：按「现在这一发弹」的真弹道（Ballistics.superElev）每 200 米一格、每 400 米写数（百米），
--     画在「比装定的距离多抬 / 少抬多少」的地方——装定 0 米时全在中心下面（截图那样）；装定 1200 米时「12」正好在中心，近的在上面、远的在下面。
--     装定距离：PageUp / PageDown 每次 100 米（手动），R 测距以后自动装定（没有激光测距机的是车长估距）
--   · 苏式光学（TSh、TPD）上方还有各弹种的距离表尺 + 一根指示线（真镜子摇表尺手轮挪这根线），左下 2.7 米高目标的测距曲线
local S = {}

S.UNIT = { east = 6000, west = 6400 }

-- 每一家分划（FAMILY）：
--   unit 密位制；center 瞄准标（chev 苏式 ^ 尖、box 方框、cross 十字留空、dot 十字 + 圆点）；
--   lat 横线上的刻度 { step 每格几密位、label 每几密位写数、ext 刻度画到几密位、gap 中心留空几密位 }；
--   vline 中心往下那根竖线（从几密位开始）；ladder 表尺（"left" 竖线左边一列刻度，"bars" 北约式横杠）；
--   top 上方各弹种表尺；stadia 测距曲线（目标高几米）；digital 镜下数字读数（距离、弹种、待发）
S.FAMILY = {
  -- 苏式光学 TSh 系列（TSh-2B-32P、TSh-2B-41……：59 / 69 式、BMP-1 的 1PN22、BRDM-2 的 PP-61AM 照这个样子）
  tsh = { unit = 6000, center = "chev", lat = { step = 4, label = 8, ext = 32, gap = 3 }, vline = 3, ladder = "left", top = true, stadia = 2.7, digital = false,
    zh = "TSh 光学瞄准镜", en = "TSh optical sight" },
  -- 苏式测距瞄准镜 TPD-2 / TPD-K1（T-64A / B、T-72 乌拉尔 / A）：同 TSh 的分划，TPD-K1 有激光测距（镜下四位数）
  tpd = { unit = 6000, center = "chev", lat = { step = 4, label = 8, ext = 32, gap = 3 }, vline = 3, ladder = "left", top = true, stadia = 2.7, digital = "lrf",
    zh = "TPD 测距瞄准镜", en = "TPD rangefinder sight" },
  -- 苏式 / 中式数字火控（1G42、1G46、「松树-U」、96 / 99 式）：^ 尖 + 两边横线，镜下距离、弹种、待发；弹道计算机自动装定，没有下坠刻度
  sovmod = { unit = 6000, center = "chev", lat = { step = 4, label = 8, ext = 24, gap = 4 }, vline = 4, vlen = 10, ladder = nil, top = false, stadia = nil, digital = true,
    zh = "数字火控瞄准镜", en = "Digital FCS sight" },
  -- 北约早期弹道分划（M60 的 M105D、豹 1 的 TZF、M551、74 式早期）：细十字留空、中心往下一排各距离的横杠（北约式表尺）
  nato1 = { unit = 6400, center = "cross", lat = { step = 5, label = 10, ext = 30, gap = 2 }, vline = 2, ladder = "bars", top = false, stadia = nil, digital = false,
    zh = "弹道分划望远镜", en = "Ballistic telescope" },
  -- 北约激光测距 + 模拟计算机（M60A3 TTS、M1 / M1A1 的 GPS、豹 1A5、豹 2A4 的 EMES-15）：方框瞄准标、两边横线
  natolrf = { unit = 6400, center = "box", lat = { step = 5, label = 10, ext = 30, gap = 4 }, vline = 4, vlen = 14, ladder = nil, top = false, stadia = nil, digital = true,
    zh = "激光测距瞄准镜", en = "LRF sight" },
  -- 北约数字火控（M1A2 / SEP、豹 2A6 / 2A7V、勒克莱尔、10 式）：十字留空 + 圆点
  natodig = { unit = 6400, center = "dot", lat = { step = 5, label = 10, ext = 20, gap = 3 }, vline = 3, vlen = 12, ladder = nil, top = false, stadia = nil, digital = true,
    zh = "数字火控瞄准镜", en = "Digital FCS sight" },
}

-- 按科技树的键指定（先查它：同一个模型的不同版本——us_m2 和 m2a3、de_leo2a0 和 2a4、cn_96 和 96b——镜子不一样），再按型号，都没写的按 WtOptics.kit 推。
--   真车：TSh-2-22（59 式仿制）、TPD-2-49（T-64A、T-72 乌拉尔：镜内光学测距）、TPD-K1（T-72A / B：激光）、1G42（T-64B、T-80B）、1G46（T-80U、T-90A）、
--   松树-U（T-72B3、T-80BVM、T-90M）；1PN22（BMP-1、86 式）、BPK（BMP-2）；M105D（M60、M60A1）、TZF（豹 1）；GPS（M1 / IPM1 / M1A1）、
--   EMES-15（豹 2A0～A4）；74 式有红宝石激光测距 + 模拟计算机（激光一代）；87 式侦察警戒车没有激光（VehDefs NO_LRF）
S.TREE = {
  cn_59 = "tsh", cn_t3485 = "tsh", cn_su100 = "tsh", cn_86 = "tsh", ru_bmp1 = "tsh", ru_bmp2 = "tsh", ru_brdm2 = "tsh", ru_strela1 = "tsh",
  cn_69 = "tpd", ru_t64a = "tpd", ru_t72 = "tpd", ru_t72a = "tpd", ru_t72b = "tpd",
  ru_t64b = "sovmod", ru_t80b = "sovmod", ru_t80u = "sovmod", ru_t90a = "sovmod", ru_t72b3 = "sovmod", ru_t80bvm = "sovmod", ru_t90m = "sovmod",
  ru_bmp2m = "sovmod", ru_pantsir = "sovmod",
  cn_96 = "sovmod", cn_96a = "sovmod", cn_96b = "sovmod", cn_99 = "sovmod", cn_99a = "sovmod", cn_pgl625 = "sovmod",
  us_m60 = "nato1", us_m60a1 = "nato1", us_m60a1rise = "nato1", us_m551 = "nato1", us_m2 = "nato1", us_m2a2 = "nato1",
  us_m60a3 = "natolrf", us_m1 = "natolrf", us_m1ip = "natolrf", us_m1a1 = "natolrf", us_m1a1hc = "natolrf",
  us_m1a2 = "natodig", us_m1a2sep = "natodig", us_m1a2sep2 = "natodig", us_m1a2sep3 = "natodig", us_m2a3 = "natodig",
  de_leo1 = "nato1", de_kpz70 = "nato1", de_marder1a3 = "nato1", de_leo1a1a1 = "nato1", de_leo1a5 = "natolrf", de_leo2a0 = "natolrf", de_leo2a4 = "natolrf",
  de_leo2a5 = "natodig", de_leo2a6 = "natodig", de_leo2a7v = "natodig",
  jp_type74 = "natolrf", jp_type74g = "natolrf", jp_type10 = "natodig", jp_type87rcv = "nato1",
}
S.VEH = {
  type59 = "tsh", t3485 = "tsh", su100 = "tsh", bmp1 = "tsh", bmp2 = "tsh", brdm2 = "tsh", strela1 = "tsh",
  type69 = "tpd", t64a = "tpd", t72ural = "tpd", t72a = "tpd", t72b = "tpd",
  t64b = "sovmod", t80b = "sovmod", t80u = "sovmod", t80bvm = "sovmod", t90m = "sovmod", t72b3 = "sovmod", ztz96 = "sovmod", ztz99a = "sovmod", bmp2m = "sovmod", pantsir = "sovmod",
  m60a1 = "nato1", m551 = "nato1", leo1 = "nato1", kpz70 = "nato1", type87rcv = "nato1",
  m60a3 = "natolrf", m1a1 = "natolrf", leo1a5 = "natolrf", leo2a4 = "natolrf", type74 = "natolrf", type74g = "natolrf",
  marder1a3 = "nato1", m1a2 = "natodig", leo2a6 = "natodig", leo2a7v = "natodig", leclerc = "natodig", type10 = "natodig", m2a3 = "natodig",
}

-- 这辆车用哪一家分划：kit = WtOptics.kit(...)（{ ret, east, gen … }），vid 型号，treeKey 科技树的键（可空）
function S.familyOf(kit, vid, treeKey)
  local name = (treeKey and S.TREE[treeKey]) or (vid and S.VEH[vid])
  if not name then
    local ret = kit and kit.ret or "dig"
    local east = kit and kit.east == true
    if ret == "sov" then name = "tsh"
    elseif ret == "nato" then name = east and "tsh" or "nato1"
    elseif ret == "lrf" then name = east and "tpd" or "natolrf"
    else name = east and "sovmod" or "natodig" end
  end
  return name, S.FAMILY[name]
end

-- 一密位是多少弧度
function S.rad(unit) return 2 * math.pi / (unit or 6000) end

-- 表尺刻度：BAL = Ballistics 模块，a = 这发弹（Ballistics.AMMO 的一项），R0 = 装定距离（米），unit 密位制
--   返回 { { r = 米, y = 密位（往下为正）, label = "4" / nil（每 400 米写百米数） } … }；破甲 / 榴弹 3 公里内、穿甲 4 公里内
function S.ladder(BAL, a, R0, unit)
  if not a or a.cls == "atgm" or a.cls == "can" then return {} end
  local rmax = ({ ap = 4000, jet = 3000, heat = 3000, mpat = 3000, he = 4000 })[a.cls] or 3000
  local k = 1 / S.rad(unit)
  local th0 = (R0 and R0 >= 1) and BAL.superElev(a, R0, 0) or 0
  local out = {}
  for r = 200, rmax, 200 do
    local th = BAL.superElev(a, r, 0)
    table.insert(out, { r = r, y = (th - th0) * k, label = (r % 400 == 0) and tostring(r // 100) or nil })
  end
  return out
end

-- 上方各弹种表尺（苏式）：这门炮的每种弹一列（穿甲、破甲、榴弹……，不画导弹、霰弹、射流），同一个「多抬几密位」的比例尺——
--   指示线一根横着跨所有列，读哪一列就是那种弹装定了多远（真 TSh 镜子的表尺就是这么排的）
--   返回 { cols = { { key, cls, ticks = { { r, t（0 顶 … 1 底）, label } … } } … }, ind = 指示线位置（0…1），thMax }
function S.topScales(BAL, wid, curKey, R0)
  local list = BAL.GUN[wid or ""]
  if not list then return nil end
  local RMAX = { ap = 4000, heat = 3000, mpat = 3000, he = 4000 }
  local cols, thMax = {}, 0
  for _, key in ipairs(list) do
    local a = BAL.AMMO[key]
    local rm = a and RMAX[a.cls]
    if rm and #cols < 3 then
      local th = BAL.superElev(a, rm, 0)
      if th > thMax then thMax = th end
      table.insert(cols, { key = key, cls = a.cls, a = a, rmax = rm })
    end
  end
  if #cols == 0 or thMax <= 0 then return nil end
  for _, c in ipairs(cols) do
    c.ticks = {}
    for r = 0, c.rmax, 200 do
      local th = (r >= 1) and BAL.superElev(c.a, r, 0) or 0
      table.insert(c.ticks, { r = r, t = th / thMax, label = (r % 800 == 0 and r > 0) and tostring(r // 100) or nil })
    end
  end
  local cur = BAL.AMMO[curKey or ""]
  local ind = (cur and R0 and R0 >= 1) and (BAL.superElev(cur, R0, 0) / thMax) or 0
  return { cols = cols, ind = math.clamp(ind, 0, 1), thMax = thMax }
end

-- 测距曲线（2.7 米高的目标）：每个距离（百米）上目标有多高（密位）——量的时候把目标卡在底线和曲线之间
S.STADIA_R = { 4, 6, 8, 10, 15, 20, 30 }   -- 常用的 400 米～2 公里那段要有刻度（远了 2.7 米的车只剩一两个像素）
function S.stadiaMils(h, rHundreds, unit)
  return (h / (rHundreds * 100)) / S.rad(unit)
end

-- 车长望远镜（用户 11-27「再做一个望远镜」）：8 倍、视场约 8.75°（真的军用望远镜 8×30），6000 制密位分划（苏式 BPC 那种）
S.BINOC = { mag = 8, mags = { 2, 4, 6, 8, 10, 12 }, unit = 6000, lat = { step = 5, label = 10, ext = 40 }, vstep = 5, vext = 20, stadia = 2.7 }   -- 北约的车用 6400 制（GunSight 按 kit.east 换）；mags：滚轮换的倍率（用户 11-28「望远镜要能缩放」，举起来默认 mag）

-- 方位刻度（瞄准镜顶上）：镜头朝向（偏航，逆时针、从 −Z 起，弧度）→ 航向（顺时针从北，度，0 ~ 360）
function S.heading(yaw)
  local d = math.deg(yaw or 0) % 360
  return (360 - d) % 360
end
-- 刻度间隔：一度多少像素（pxPerDeg）→ 小刻度每几度、写数每几度（字之间至少 70 像素、小刻度至少 9 像素）
function S.tapeSteps(pxPerDeg)
  local minor, major = 1, 5
  for _, s in ipairs({ 1, 2, 5, 10, 15, 30 }) do
    if s * pxPerDeg >= 9 then minor = s break end
    minor = s
  end
  for _, s in ipairs({ 1, 2, 5, 10, 15, 30, 45, 90 }) do
    if s >= minor and s % minor == 0 and s * pxPerDeg >= 70 then major = s break end
    major = s
  end
  return minor, major
end

return S
