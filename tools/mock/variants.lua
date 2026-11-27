-- 拆开重叠的版本（用户 11-27「把重叠的版本拆开（M1A2 / SEP / SEPv3 等）」「各维度还原一致」）：python3 tools/mock/run.py tools/mock/variants.lua
--   不开服，只读共用的数据模块（一秒内跑完）：
--   ① 爆反老 bug：借同族模型、真车没有爆反的型号（VehDefs 的 noEra）TankMods.eraOf 是 nil、一格都不贴、没有改装页；有爆反的照旧
--   ② 科技树原来写 base（模型、性能都借）的地面项：有自己的型号（veh）、借同族的模型（model），不再是「暂用」；TT.byVeh 找得回这一项
--   ③ 每个拆出来的型号：同族模型（like、ImportedMeta 的 alias 跟同族一样、炮塔转轴照模型）、炮和弹种表（每种弹有弹道和穿深，
--      第一种是原厂弹、射流弹在最后）、装甲表、名字（中英文，炮也有）、夜视、写实图、驾驶界面的剪影（没有自己的就退到同族）
--   ④ 跟同族比真的不一样（炮 / 弹、加速、炮塔正面装甲至少一样），数值在合理范围；同一族按年代往上走（默认弹的穿深、炮塔正面装甲）
--   ⑤ 改装页：noEra 的没有；有爆反的同族变型退到同族那一套（TankMods.FOR），车重按自己的（TankMods.SPEC）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3 = T.R, T.V3
local check = T.check
local t0 = os.clock()
T.scripts = dofile(MOCK_DIR .. "/load.lua")(R, SRC_DIR)
local RS = R.services.ReplicatedStorage
local function req(n) return R.require(RS:FindFirstChild(n)) end
local VD, TM, TT, B, WD = req("VehDefs"), req("TankMods"), req("TechTree"), req("Ballistics"), req("WtDamage")
local IM, OPT, WM, Lang, VP = req("ImportedMeta"), req("WtOptics"), req("WtMods"), req("Lang"), req("VehPics")
local function cnt(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
local function near(a, b) return a ~= nil and b ~= nil and (a - b).Magnitude < 0.02 end
local function has(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end return false end
-- HudIcons 有 1.5 MB：只看键在不在，不整个载入
local hudKeys = {}
do
  local f = io.open(SRC_DIR .. "/ReplicatedStorage/HudIcons.lua")
  local s = f and f:read("a") or ""
  if f then f:close() end
  for k in s:gmatch("\n  ([%w_]+) = { w = ") do hudKeys[k] = true end
end

-- 拆出来的每一项：{ 科技树的键, 新型号, 同族型号（VehDefs 的 like = 科技树的 model）, noEra, nv 夜视, fam 族（年代顺序检查用） }
--   gen 原厂火控第几代（WtMods.fcsGen：2 激光 + 模拟计算机、3 数字、4 猎歼）
local SPLIT = {
  -- 第 1 批：美国 M1 一族（M1A1 / M1A2 SEPv2 原来就有）
  { "us_m1", "m1", "m1a1", noEra = true, nv = "th1", gen = 2 },
  { "us_m1ip", "m1ip", "m1a1", noEra = true, nv = "th1", gen = 2 },
  { "us_m1a1hc", "m1a1hc", "m1a1", noEra = true, nv = "th1", gen = 2 },
  { "us_m1a2", "m1a2base", "m1a2", noEra = true, nv = "th1", gen = 4 },
  { "us_m1a2sep", "m1a2sep", "m1a2", noEra = true, nv = "th2", gen = 4 },
  { "us_m1a2sep3", "m1a2sep3", "m1a2", nv = "th3", gen = 4 },
  -- 第 2 批：M60 两型、豹三型（M60A1 / M60A3、豹 1 / 1A5、豹 2A4 / 2A6 原来就有）
  { "us_m60", "m60", "m60a3", nv = "ir", gen = 0 },
  { "us_m60a1rise", "m60a1rise", "m60a3", nv = "ii", gen = 1 },
  { "de_leo1a1a1", "leo1a1a1", "leo1", nv = "ir", gen = 1 },
  { "de_leo2a0", "leo2a0", "leo2a6", nv = "ii", gen = 2 },
  { "de_leo2a5", "leo2a5", "leo2a6", nv = "th1", gen = 3 },
  -- 第 3 批：中国 96 / 96A / 99 式、86 式，俄 T-90A，美 M2 / M2A2（96B、99A、BMP-1、T-90M、M2A3 原来就有；86 式、布雷德利不是坦克炮，没有火控代）
  { "cn_96", "ztz96base", "ztz96", noEra = true, nv = "ii", gen = 3 },
  { "cn_96a", "ztz96a", "ztz96", nv = "th2", gen = 4 },
  { "cn_99", "ztz99base", "ztz99a", nv = "th1", gen = 3 },
  { "cn_86", "type86", "bmp1", nv = "ir" },
  { "ru_t90a", "t90a", "t90m", nv = "th2", gen = 3 },
  { "us_m2", "m2a0", "m2a3", nv = "th1" },
  { "us_m2a2", "m2a2", "m2a3", nv = "th1" },
}
-- 一族里按年代排的型号（拆出来的 + 原来就有的）：默认弹的穿深、炮塔正面装甲（动能）不往回掉；skip 不比的（年代错位的老车，写进回报）
local FAMILY = {
  { name = "M1 一族", ids = { "m1", "m1ip", "m1a1", "m1a1hc", "m1a2base", "m1a2sep", "m1a2", "m1a2sep3" },
    skip = { m1a1 = true } },   -- M1A1（1985）打的是 M829A3（2003 年的弹）：原来就有的年代错位，不在这次拆的范围
  { name = "M60 一族", ids = { "m60", "m60a1", "m60a1rise", "m60a3" } },
  { name = "豹 1", ids = { "leo1", "leo1a1a1", "leo1a5" } },
  { name = "豹 2", ids = { "leo2a0", "leo2a4", "leo2a5", "leo2a6", "leo2a7v" } },
  { name = "96 系", ids = { "ztz96base", "ztz96a", "ztz96" } },
  { name = "99 系", ids = { "ztz99base", "ztz99a" } },
  { name = "T-90", ids = { "t90a", "t90m" } },
  { name = "布雷德利", ids = { "m2a0", "m2a2", "m2a3" },
    skip = { m2a3 = true } },   -- M2A3 用的是 30 毫米 ac30（真车是 M242 25 毫米）：原来就有的年代错位
}
-- 借同族模型、真车没有爆反的老车（11-27 一起修的老 bug：原来 T-80B 22 格接触-5、T-72 乌拉尔 / A / B 各 37 格）
local NOERA_OLD = { "t80b", "t72ural", "t72a", "t72b" }
-- 自己有爆反的照旧（几格是 11-27 修之前探针量的）
local KEEP = { { "t80u", 22 }, { "t80bvm", 22 }, { "t72b3", 37 }, { "ztz96", 36 }, { "m1a1", 26 }, { "m1a2", 10 } }

print("① 爆反：借来的模型上后来才有的块不起作用")
for _, id in ipairs(NOERA_OLD) do
  local d = VD.get(id)
  local n = cnt(TM.cellsOn(id))
  check(d ~= nil and d.noEra == true and TM.eraOf(id) == nil and n == 0 and not TM.has(id),
    string.format("%s：noEra，eraOf 是 nil、贴了 %d 格、没有改装页", id, n))
end
for _, s in ipairs(SPLIT) do
  if s.noEra then
    local n = cnt(TM.cellsOn(s[2]))
    check(TM.eraOf(s[2]) == nil and n == 0 and not TM.has(s[2]), string.format("%s（%s）：真车没有爆反，借来的模型上的块不起作用（%d 格）", s[2], s[1], n))
  end
end
for _, k in ipairs(KEEP) do
  local n = cnt(TM.cellsOn(k[1]))
  check(TM.eraOf(k[1]) ~= nil and n == k[2], string.format("%s：自己的爆反照旧（%d 格，原来 %d 格）", k[1], n, k[2]))
end

print("② 科技树：原来写 base 的地面项有了自己的型号")
do
  local left = {}
  for _, nat in ipairs(TT.NATIONS) do
    for _, it in ipairs(TT.list[nat].ground) do
      if it.base ~= nil or it.stand then table.insert(left, it.key .. "→" .. tostring(it.base)) end
    end
  end
  check(#left == 0, "地面树没有一项还写 base（模型、性能都借：「暂用」）" .. (#left > 0 and ("：" .. table.concat(left, " ")) or ""))
end
for _, s in ipairs(SPLIT) do
  local it = TT.get(s[1])
  check(it ~= nil and it.veh == s[2] and it.play == s[2] and it.model == s[3] and it.base == nil and not it.stand and TT.byVeh[s[2]] == it,
    string.format("%s：开 %s、模型借同族的 %s（科技树写「同族模型」）", s[1], tostring(it and it.play), tostring(it and it.model)))
end

print("③ 每个型号的数据齐全")
local GRID = 2.8
for _, s in ipairs(SPLIT) do
  local key, vid, like = s[1], s[2], s[3]
  local d, dl = VD.get(vid), VD.get(like)
  local bad = {}
  local function need(ok, what) if not ok then table.insert(bad, what) end end
  need(d ~= nil and dl ~= nil, "型号")
  if d and dl then
    need(d.like == like, "like")
    local mk = IM.alias[vid]
    need(mk ~= nil and mk == IM.alias[like] and d.model == mk, "模型 alias（" .. tostring(mk) .. "）")
    local info = mk and IM.m[mk]
    if info and info.tur then
      local tur = V3(info.tur[1], info.tur[2], info.tur[3])
      need(near(d.turret.pivot, tur), "炮塔转轴照模型")
      if info.gun then need(near(d.gun.pivot, V3(info.gun[1], info.gun[2], info.gun[3]) - tur), "炮耳轴照模型") end
    end
    need(d.weapons ~= dl.weapons and d.turret ~= dl.turret, "深拷（各有一份武器表、炮塔）")
    for _, w in ipairs(d.weapons) do
      need(VD.W[w] ~= nil, "武器 " .. w)
      need(Lang.zh["vw." .. w] ~= nil and Lang.en["vw." .. w] ~= nil, "武器名 vw." .. w)
      local W = VD.W[w]
      if W and w ~= "coax" and not B.GUN[w] then need(WD.WPN[w] ~= nil, "穿深 WtDamage.WPN." .. w) end
    end
    local w1 = d.weapons[1]
    local list = B.GUN[w1]
    if d.cat == "tank" then
      need(list ~= nil, "弹种表 Ballistics.GUN." .. tostring(w1))
      for i, am in ipairs(list or {}) do
        need(B.AMMO[am] ~= nil, "弹道 " .. am)
        need(WD.AMMO[am] ~= nil, "穿深 " .. am)
        if i == 1 then need(not am:match("^jet"), "第一种是原厂弹") end
      end
      if list and #list > 1 then need(list[#list]:match("^jet") ~= nil, "射流弹在最后") end
      local a1 = list and B.AMMO[list[1]]
      if a1 and VD.W[w1] then need(math.abs(VD.W[w1].speed - a1.v0 * GRID) < 2, string.format("炮的 speed（%.0f）= 默认弹初速 × 2.8", VD.W[w1].speed)) end
    end
    need(WD.PROF[vid] ~= nil, "装甲 WtDamage.PROF")
    need(Lang.zh["veh." .. vid] ~= nil and Lang.en["veh." .. vid] ~= nil, "名字 veh." .. vid)
    need(OPT.VEH_NV[vid] == s.nv and OPT.TREE_NV[key] == s.nv, string.format("夜视 %s（型号 %s、科技树 %s）", s.nv, tostring(OPT.VEH_NV[vid]), tostring(OPT.TREE_NV[key])))
    need(VP.veh and VP.veh[vid] ~= nil and VP.veh[vid] == VP.veh[like], "写实图（VehPics）")
    need(hudKeys["veh_" .. vid] or hudKeys["veh_" .. like], "剪影（HudIcons，退到同族）")
    need((d.noEra == true) == (s.noEra == true), "noEra")
    need(d.turbine == dl.turbine, "发动机（燃气轮机）跟同族一样")
    -- 电脑车（AIVeh 的 usable、Tech.lua 的 G.treePickAi）按科技树的 it.play 挑：型号的车种、武器要对得上
    need(d.cat == dl.cat and (d.cat == "tank" or d.cat == "apc") and #d.weapons > 0 and not d.needsAir, "车种 / 武器（电脑车挑得到）")
  end
  check(#bad == 0, string.format("%s（%s ← %s）：%s", vid, key, like, #bad == 0 and "齐全" or table.concat(bad, "；")))
end

print("④ 跟同族真的不一样、数值合理")
local function profTf(id) local P = WD.PROF[id] return P and P.tur and P.tur.f and P.tur.f[1] or (P and P.hull.f[1]) end
local function pen0(id)
  local d = VD.get(id)
  local w1 = d and d.weapons[1]
  local list = w1 and B.GUN[w1]
  if list then local a = WD.AMMO[list[1]] return a and a.p0 end
  local a = w1 and WD.WPN[w1]
  return a and a.p0
end
for _, s in ipairs(SPLIT) do
  local d, dl = VD.get(s[2]), VD.get(s[3])
  if d and dl then
    local diff = {}
    if d.weapons[1] ~= dl.weapons[1] or table.concat(d.weapons, ",") ~= table.concat(dl.weapons, ",") then table.insert(diff, "武器") end
    if math.abs((d.accel or 0) - (dl.accel or 0)) > 0.05 then table.insert(diff, "加速") end
    if math.abs(d.speed - dl.speed) > 0.05 then table.insert(diff, "极速") end
    if profTf(s[2]) ~= profTf(s[3]) then table.insert(diff, "装甲") end
    if OPT.VEH_NV[s[2]] ~= OPT.VEH_NV[s[3]] then table.insert(diff, "夜视") end
    local tank = d.cat == "tank"
    local tf, p = profTf(s[2]) or 0, pen0(s[2]) or 0
    local okR = d.speed >= 30 and d.speed <= 60 and d.accel >= 2.5 and d.accel <= 7.5 and (d.rev or 0) > 0
      and (tank and (tf >= 150 and tf <= 1000 and p >= 250 and p <= 950) or (not tank and tf >= 20 and tf <= 150 and p >= 50))
    check(#diff > 0 and okR, string.format("%s 跟 %s 不一样（%s）；极速 %.1f、加速 %.1f、炮塔正面 %d 毫米、默认弹穿深 %d 毫米", s[2], s[3],
      #diff > 0 and table.concat(diff, "、") or "一模一样", d.speed, d.accel, tf, p))
  end
end
for _, F in ipairs(FAMILY) do
  local back = {}
  local lastP, lastA, lastId = -1, -1, nil
  for _, id in ipairs(F.ids) do
    if not (F.skip and F.skip[id]) then
      local p, a = pen0(id) or 0, profTf(id) or 0
      if p < lastP or a < lastA then table.insert(back, string.format("%s（穿深 %d、装甲 %d）比 %s 还低", id, p, a, tostring(lastId))) end
      lastP, lastA, lastId = math.max(lastP, p), math.max(lastA, a), id
    end
  end
  check(#back == 0, F.name .. "：按年代默认弹穿深、炮塔正面装甲不往回掉" .. (#back > 0 and ("：" .. table.concat(back, "；")) or ""))
end

print("⑤ 各族自己的")
do
  local m1, hc, a2, sep3 = VD.get("m1"), VD.get("m1a1hc"), VD.get("m1a2base"), VD.get("m1a2sep3")
  if m1 and hc and a2 and sep3 then
    check(m1.citv == nil and hc.citv == nil and a2.citv ~= nil and sep3.citv ~= nil, "车长独立热像仪（CITV，猎歼）M1A2 起才有")
    check(B.GUN[m1.weapons[1]][1] == "m774" and B.GUN[hc.weapons[1]][1] == "m829a1" and B.GUN[sep3.weapons[1]][1] == "m829a4"
      and table.concat(B.GUN[sep3.weapons[1]], ","):find("m829a3", 1, true) ~= nil,
      "M1 打 105 毫米 M774、M1A1 HC 打 M829A1、SEPv3 打 M829A4（弹药数据链）也能打 M829A3")
    local F = TM.FOR.m1a2sep3
    check(F ~= nil and has(F.aps, "trophy") and has(F.era, "arat") and not TM.has("m1a2sep") and not TM.has("m1"),
      "TUSK（ARAT）/ Trophy 只有 SEPv3 能装（M1～SEP 没有改装页）")
    check(m1.turbine and sep3.turbine and m1.speed > hc.speed and m1.accel > sep3.accel, "燃气轮机；M1 / IPM1 限速 72、M1A1 起 67 公里 / 时；越重加速越慢")
  end
end

do
  local m60, a1, rise, l1, l2a0, l2a5 = VD.get("m60"), VD.get("m60a1"), VD.get("m60a1rise"), VD.get("leo1a1a1"), VD.get("leo2a0"), VD.get("leo2a5")
  if m60 and a1 and rise and l1 and l2a0 and l2a5 then
    check(m60.noStab == true and not a1.noStab and not rise.noStab and profTf("m60") < profTf("m60a1") and m60.accel > a1.accel,
      "M60 没有稳定器（noStab）、M48 式短炮塔比 M60A1 薄、车轻加速快")
    check(B.GUN[rise.weapons[1]][1] == "m735" and m60.weapons[1] == a1.weapons[1], "M60A1 RISE 打 M735；M60 同 M60A1 打 M392")
    check(not m60.lrf and not rise.lrf and not l1.lrf and l2a0.lrf and VD.get("m60a3").lrf, "合像 / 体视测距的没有激光（M60、RISE、豹 1A1A1），豹 2A0、M60A3 有")
    check(l2a5.weapons[1] == "gun120l44" and VD.get("leo2a6").weapons[1] == "gun120l55" and B.GUN[l2a0.weapons[1]][1] == "dm13l44",
      "豹 2A5 还是 L/44（L/55 是 2A6 才换的）、豹 2A0 打 DM13")
    check(OPT.TREE_NV.de_leo1a1a1 == "ir" and OPT.TREE_NV.de_leo2a0 == "ii", "豹 1A1A1 主动红外（PZB 200 微光是 1A1A2 才有）、豹 2A0 微光")
  end
end

do
  local z96, z96a, z99, t90a, t86, m2, m2a2 = VD.get("ztz96base"), VD.get("ztz96a"), VD.get("ztz99base"), VD.get("t90a"), VD.get("type86"), VD.get("m2a0"), VD.get("m2a2")
  if z96 and z96a and z99 and t90a and t86 and m2 and m2a2 then
    check(not TM.has("ztz96base") and TM.FOR.ztz96a and TM.FOR.ztz96a.era[1] == "fy4" and TM.FOR.ztz96.era[1] == "fy2"
      and cnt(TM.cellsOn("ztz96a")) == cnt(TM.cellsOn("ztz96")),
      "96 式没有爆反；96A 出厂 FY-4（96B 是 FY-2），块照同一个模型")
    check(TM.FOR.ztz99base == TM.FOR.ztz99a and has(TM.FOR.ztz99base.ew, "jd3") and TM.FOR.t90a == TM.FOR.t90m and has(TM.FOR.t90a.ew, "lws"),
      "99 式的改装页照 99A（JD-3 激光对抗），T-90A 照 T-90M（「窗帘」光电对抗）")
    check(WD.CAROUSEL.ztz96base and WD.CAROUSEL.ztz96a and WD.CAROUSEL.ztz99base and WD.CAROUSEL.t90a, "转盘式自动装弹机：殉爆时炮塔飞（96 / 96A / 99 / T-90A）")
    check(has(t86.weapons, "hj73") and not has(t86.weapons, "malyutka") and t86.weapons[1] == VD.get("bmp1").weapons[1] and not t86.lrf,
      "86 式：同 BMP-1 的 73 毫米炮，导弹是红箭-73，没有激光测距")
    check(m2.weapons[1] == "m242" and has(m2.weapons, "tow1") and m2a2.weapons[1] == "m242" and has(m2a2.weapons, "tow2") and not WD.WPN.tow1.tandem
      and not m2.lrf and not m2a2.lrf and VD.get("m2a3").lrf,
      "M2 / M2A2：M242 25 毫米，M2 打单装药的改进型陶式、M2A2 打陶式 2；ISU 没有激光测距（M2A3 有）")
    check(Lang.zh["veh.ztz96"] == "96B 式主战坦克", "ztz96 改名叫 96B（它本来就是 96B）：" .. tostring(Lang.zh["veh.ztz96"]))
  end
end

print("⑥ 改装页、火控")
for _, s in ipairs(SPLIT) do
  local d = VD.get(s[2])
  if d and not s.noEra and TM.FOR[s[3]] then
    local st = TM.stats(s[2], nil)
    check(TM.has(s[2]) and st ~= nil and TM.SPEC[s[2]] ~= nil and TM.SPEC[s[2]] ~= TM.SPEC[s[3]] and cnt(TM.cellsOn(s[2])) > 0,
      string.format("%s：改装页%s（爆反 %s，%d 格），车重按自己的 %.1f 吨", s[2], (TM.FOR[s[2]] == TM.FOR[s[3]]) and ("照同族 " .. s[3]) or "单独登记的一套",
        tostring(TM.FOR[s[2]] and TM.FOR[s[2]].era[1]),
        cnt(TM.cellsOn(s[2])), TM.SPEC[s[2]] and TM.SPEC[s[2]].t or 0))
  end
  if s.gen then
    local g = WM.fcsGen(TT.get(s[1]))
    check(g == s.gen, string.format("%s：原厂火控第 %s 代（应为 %d）", s[1], tostring(g), s.gen))
  end
end

local dt = os.clock() - t0
check(dt < 1.5, string.format("跑了 %.2f 秒（不开服）", dt))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
