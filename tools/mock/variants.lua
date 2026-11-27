-- 拆开重叠的版本（用户 11-27「把重叠的版本拆开（M1A2 / SEP / SEPv3 等）」「各维度还原一致」）：python3 tools/mock/run.py tools/mock/variants.lua
--   不开服，只读共用的数据模块（一秒内跑完）：
--   ① 爆反老 bug：借同族模型、真车没有爆反的型号（VehDefs 的 noEra）TankMods.eraOf 是 nil、一格都不贴、没有改装页；有爆反的照旧
--   ② 科技树原来写 base（模型、性能都借）的地面项：有自己的型号（veh）、借同族的模型（model），不再是「暂用」；TT.byVeh 找得回这一项
--   ③ 每个拆出来的型号：同族模型（like、ImportedMeta 的 alias 跟同族一样、炮塔转轴照模型）、炮和弹种表（每种弹有弹道和穿深，
--      第一种是原厂弹、射流弹在最后）、装甲表、名字（中英文，炮也有）、夜视、写实图、驾驶界面的剪影（没有自己的就退到同族）
--   ④ 跟同族比真的不一样（炮 / 弹、加速、炮塔正面装甲至少一样），数值在合理范围；同一族按年代往上走（默认弹的穿深、炮塔正面装甲）
--   ⑤ 改装页：noEra 的没有；有爆反的同族变型退到同族那一套（TankMods.FOR），车重按自己的（TankMods.SPEC）
--   11-27 审查以后加的：⑦ 弹种顺序 { 原厂穿甲, 破甲 / 多用途, 榴弹 / MPAT / 霰弹, 旧穿甲…, 射流 }；
--   ⑧ 年代错位修正：科技树的 M1A1 开 m1a1base（老 m1a1 不动）、导弹单装药按 k、59 / 69 式的剪影、M60 火控第 1 代、没有稳定器的车、M2A3 的 M919……
--   11-27 二审加的：④ 研究满以后（前三种弹里最强的）穿深同一族、科技树同一列按年代不往回掉；⑦ 车里炮长面板的弹种键（Ballistics.panelAmmo）；
--   ⑧ M791 的穿深照战雷
--   （第一人称车内退 like 在 fponly.lua；电脑车真按科技树挑得到在 wtreal.lua ②；单装药导弹真打爆反在 tankkit.lua ④——这几条要开服）
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
  -- 11-27 审查第 1 条：科技树的 M1A1 原来直接开老的 m1a1（M829A3、ARAT）；ownModel：模型就是 M1A1 自己的，科技树不写 model（二审：写了会标「同族模型」）
  { "us_m1a1", "m1a1base", "m1a1", noEra = true, nv = "th1", gen = 2, ownModel = true },
  { "us_m1a1hc", "m1a1hc", "m1a1", noEra = true, nv = "th1", gen = 2 },
  { "us_m1a2", "m1a2base", "m1a2", noEra = true, nv = "th1", gen = 4 },
  { "us_m1a2sep", "m1a2sep", "m1a2", noEra = true, nv = "th2", gen = 4 },
  { "us_m1a2sep3", "m1a2sep3", "m1a2", nv = "th3", gen = 4 },
  -- 第 2 批：M60 两型、豹三型（M60A1 / M60A3、豹 1 / 1A5、豹 2A4 / 2A6 原来就有）
  { "us_m60", "m60", "m60a3", nv = "ir", gen = 1 },   -- 11-27：M17 合像测距 + 机械弹道计算机（WtMods.GEN_FIX，原来按年份落到 0）
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
-- 一族里按年代排的型号（拆出来的 + 原来就有的）：默认弹的穿深、炮塔正面装甲（动能）不往回掉
--   11-27 审查：原来 M1A1（打 M829A3）、M2A3（30 毫米 ac30）年代错位、skip 了不比——现在科技树的 M1A1 是 m1a1base（M829）、M2A3 换了 M242 + M919，都不跳
local FAMILY = {
  { name = "M1 一族", ids = { "m1", "m1ip", "m1a1base", "m1a1hc", "m1a2base", "m1a2sep", "m1a2", "m1a2sep3" } },
  { name = "M60 一族", ids = { "m60", "m60a1", "m60a1rise", "m60a3" } },
  { name = "豹 1", ids = { "leo1", "leo1a1a1", "leo1a5" } },
  { name = "豹 2", ids = { "leo2a0", "leo2a4", "leo2a5", "leo2a6", "leo2a7v" } },
  { name = "96 系", ids = { "ztz96base", "ztz96a", "ztz96" } },
  { name = "99 系", ids = { "ztz99base", "ztz99a" } },
  { name = "T-90", ids = { "t90a", "t90m" } },
  { name = "布雷德利", ids = { "m2a0", "m2a2", "m2a3" } },
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
  local wantModel = s[3]
  if s.ownModel then wantModel = nil end
  check(it ~= nil and it.veh == s[2] and it.play == s[2] and it.model == wantModel and it.base == nil and not it.stand and TT.byVeh[s[2]] == it,
    s.ownModel and string.format("%s：开 %s、模型是它自己的（%s 的原模型；科技树不写 model、不标「同族模型」：%s）", s[1], tostring(it and it.play), s[3], tostring(it and it.model))
      or string.format("%s：开 %s、模型借同族的 %s（科技树写「同族模型」）", s[1], tostring(it and it.play), tostring(it and it.model)))
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
    -- 车种跟同族一样、是坦克 / 步战车、有武器、不是只打飞机的（11-27 审查第 9 条：这里只看数据，原来写「电脑车挑得到」说多了——
    --   真调 Tech.lua 的 G.treePickAi + AIVeh 的 usable 要开服，在 wtreal.lua ②）
    need(d.cat == dl.cat and (d.cat == "tank" or d.cat == "apc") and #d.weapons > 0 and not d.needsAir, "车种 / 武器跟同族一样")
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
-- 研究满以后（科技树只研究得到前三种弹：WtMods 的 ammo2 / ammo3）前三种里最强的穿深也按年代不往回掉——11-27 二审：三种弹的炮第三种就是射流（研究得到）、
--   四种以上的研究不到射流；M60A1 RISE 原来第三种放 M392，研究满是 M60 一族唯一拿不到射流的（760 → 430）。同一族、科技树同一列（研究线）上下都查
local function best3(id)
  local d = VD.get(id)
  local w1 = d and d.weapons[1]
  local list = w1 and B.GUN[w1]
  if not list then return pen0(id) end
  local b = 0
  for i = 1, math.min(3, #list) do
    local a = WD.AMMO[list[i]]
    if a and a.p0 > b then b = a.p0 end
  end
  return b
end
local function noBack(ids)
  local back, last, lastId = {}, -1, nil
  for _, id in ipairs(ids) do
    local p = best3(id) or 0
    if p < last then table.insert(back, string.format("%s（%d）比 %s（%d）低", id, p, tostring(lastId), last))
    else last, lastId = p, id end
  end
  return back
end
for _, F in ipairs(FAMILY) do
  local back = noBack(F.ids)
  local vals = {}
  for _, id in ipairs(F.ids) do table.insert(vals, tostring(best3(id))) end
  check(#back == 0, F.name .. "：研究满以后（前三种弹里最强的）穿深按年代不往回掉（" .. table.concat(vals, " / ") .. "）"
    .. (#back > 0 and ("：" .. table.concat(back, "；")) or ""))
end
do
  local bad = {}
  for _, nat in ipairs(TT.NATIONS) do
    local cols, order = {}, {}
    for _, it in ipairs(TT.list[nat].ground) do
      local d = VD.get(it.play)
      if d and B.GUN[d.weapons[1]] then
        if not cols[it.col] then cols[it.col] = {} table.insert(order, it.col) end
        table.insert(cols[it.col], it.play)
      end
    end
    for _, c in ipairs(order) do
      for _, s in ipairs(noBack(cols[c])) do table.insert(bad, nat .. " 第 " .. c .. " 列 " .. s) end
    end
  end
  check(#bad == 0, "科技树同一列（研究线）上下：研究满以后的坦克炮穿深不往回掉" .. (#bad > 0 and ("：" .. table.concat(bad, "；")) or ""))
end

print("⑤ 各族自己的")
do
  local m1, hc, a2, sep3 = VD.get("m1"), VD.get("m1a1hc"), VD.get("m1a2base"), VD.get("m1a2sep3")
  if m1 and hc and a2 and sep3 then
    check(m1.citv == nil and hc.citv == nil and a2.citv ~= nil and sep3.citv ~= nil, "车长独立热像仪（CITV，猎歼）M1A2 起才有")
    check(B.GUN[m1.weapons[1]][1] == "m774" and B.GUN[hc.weapons[1]][1] == "m829a1" and B.GUN[sep3.weapons[1]][1] == "m829a4"
      and table.concat(B.GUN[sep3.weapons[1]], ","):find("m829a3", 1, true) ~= nil,
      "M1 打 105 毫米 M774、M1A1 HC 打 M829A1、SEPv3 打 M829A4（弹药数据链；M829A3 还在表里，排第四种）")
    local F = TM.FOR.m1a2sep3
    check(F ~= nil and has(F.aps, "trophy") and has(F.era, "arat") and not TM.has("m1a2sep") and not TM.has("m1"),
      "TUSK（ARAT）/ Trophy 只有 SEPv3 能装（M1～SEP 没有改装页）")
    check(m1.turbine and sep3.turbine and m1.speed > hc.speed and m1.accel > sep3.accel, "燃气轮机；M1 / IPM1 限速 72、M1A1 起 67 公里 / 时；越重加速越慢")
  end
  -- 11-27 审查第 1 条：科技树的 M1A1 原来开老的 m1a1（M829A3 穿深 800、26 格 ARAT + TUSK / Trophy 改装页），比后面的 HC、M1A2、SEP 都强
  local a1, old = VD.get("m1a1base"), VD.get("m1a1")
  if a1 and old then
    check(table.concat(B.GUN[a1.weapons[1]] or {}, ",") == "m829,m830,m829a1,jet120" and a1.noEra and TM.eraOf("m1a1base") == nil
      and not TM.has("m1a1base") and a1.speed == old.speed and a1.accel == old.accel and WD.PROF.m1a1base.tur.f[1] == WD.PROF.m1ip.tur.f[1],
      "科技树的 M1A1（m1a1base）：1985 年的 M829 / 第二种 M830 / 第三种 M829A1；没有 ARAT / TUSK（没有改装页）；炮塔同 IPM1；机动同 M1A1")
    check(old.weapons[1] == "gun120" and B.GUN.gun120[1] == "m829a3" and TM.has("m1a1") and cnt(TM.cellsOn("m1a1")) == 26 and WD.PROF.m1a1.tur.f[1] == 650
      and TT.byVeh.m1a1 == TT.get("us_m1a1") and TT.byVeh.m1a1base == TT.get("us_m1a1"),
      "老的 m1a1（老模式、老 AI 名单）不动：M829A3、26 格 ARAT、改装页；沙盒按型号找科技树照旧认 us_m1a1")
  end
end

do
  local m60, a1, rise, l1, l2a0, l2a5 = VD.get("m60"), VD.get("m60a1"), VD.get("m60a1rise"), VD.get("leo1a1a1"), VD.get("leo2a0"), VD.get("leo2a5")
  if m60 and a1 and rise and l1 and l2a0 and l2a5 then
    -- 稳定器只查 M60（没有）、RISE（有）：1962 年的 M60A1 真车也没有（AOS 1972 年才加装），照 1962 加 noStab 还是照战雷改成 M60A1 (AOS)
    --   要用户定——这里不锁（二审：原来断言「M60A1 有」，等于把一条跟公开资料相反的数据保护起来）
    check(m60.noStab == true and not rise.noStab and profTf("m60") < profTf("m60a1") and m60.accel > a1.accel,
      "M60 没有稳定器（noStab）、RISE 有；M48 式短炮塔比 M60A1 薄、车轻加速快")
    check(B.GUN[rise.weapons[1]][1] == "m735" and m60.weapons[1] == a1.weapons[1], "M60A1 RISE 打 M735；M60 同 M60A1 打 M392")
    check(not m60.lrf and not rise.lrf and not l1.lrf and l2a0.lrf and VD.get("m60a3").lrf, "合像 / 体视测距的没有激光（M60、RISE、豹 1A1A1），豹 2A0、M60A3 有")
    check(l2a5.weapons[1] == "gun120l44" and VD.get("leo2a6").weapons[1] == "gun120l55" and B.GUN[l2a0.weapons[1]][1] == "dm13l44",
      "豹 2A5 还是 L/44（L/55 是 2A6 才换的）、豹 2A0 打 DM13")
    check(OPT.TREE_NV.de_leo1a1a1 == "ir" and OPT.TREE_NV.de_leo2a0 == "ii", "豹 1A1A1 主动红外（PZB 200 微光是 1A1A2 才有）、豹 2A0 微光")
    -- 11-27 审查第 6 条：早期豹 2 是 55.15 吨、72 公里 / 时（同 2A4），原来写 68
    check(math.abs(l2a0.speed - 56.0) < 0.05 and l2a0.speed == VD.get("leo2a4").speed, string.format("豹 2A0 公路 72 公里 / 时（%.1f 格/秒，同 2A4）", l2a0.speed))
    -- 11-27（年代错位 c）：M60、M60A1 是 M17 合像测距仪 + 机械弹道计算机——第 1 代（按年份会落到 0）；M60A1 RISE、M60A3 照旧
    check(WM.fcsGen(TT.get("us_m60")) == 1 and WM.fcsGen(TT.get("us_m60a1")) == 1 and WM.fcsGen(TT.get("us_m60a1rise")) == 1
      and WM.fcsGen(TT.get("us_m60a3")) == 2,
      string.format("M60 / M60A1 原厂火控第 1 代（合像测距 + 机械计算机），RISE 1、M60A3 2（%s / %s / %s / %s）", tostring(WM.fcsGen(TT.get("us_m60"))),
        tostring(WM.fcsGen(TT.get("us_m60a1"))), tostring(WM.fcsGen(TT.get("us_m60a1rise"))), tostring(WM.fcsGen(TT.get("us_m60a3")))))
  end
end

do
  local z96, z96a, z99, t90a, t86, m2, m2a2 = VD.get("ztz96base"), VD.get("ztz96a"), VD.get("ztz99base"), VD.get("t90a"), VD.get("type86"), VD.get("m2a0"), VD.get("m2a2")
  if z96 and z96a and z99 and t90a and t86 and m2 and m2a2 then
    -- 11-27 审查第 5 条：96B 原来出厂 FY-2、比 96A 还轻；公开资料两型都是箭形 FY-4
    check(not TM.has("ztz96base") and TM.FOR.ztz96a and TM.FOR.ztz96a.era[1] == "fy4" and TM.FOR.ztz96.era[1] == "fy4"
      and TM.clean("ztz96", {}).era == "fy4" and TM.PRESETS.ztz96[1].set.era == "fy4"
      and cnt(TM.cellsOn("ztz96a")) == cnt(TM.cellsOn("ztz96")) and z96.era == false,
      "96 式没有爆反（零件拼的也不画：era = false）；96A、96B 出厂都是 FY-4（96B 原来 FY-2），块照同一个模型")
    check(TM.FOR.ztz99base == TM.FOR.ztz99a and has(TM.FOR.ztz99base.ew, "jd3") and TM.FOR.t90a == TM.FOR.t90m and has(TM.FOR.t90a.ew, "lws"),
      "99 式的改装页照 99A（JD-3 激光对抗），T-90A 照 T-90M（「窗帘」光电对抗）")
    check(WD.CAROUSEL.ztz96base and WD.CAROUSEL.ztz96a and WD.CAROUSEL.ztz99base and WD.CAROUSEL.t90a, "转盘式自动装弹机：殉爆时炮塔飞（96 / 96A / 99 / T-90A）")
    check(has(t86.weapons, "hj73") and not has(t86.weapons, "malyutka") and t86.weapons[1] == VD.get("bmp1").weapons[1] and not t86.lrf,
      "86 式：同 BMP-1 的 73 毫米炮，导弹是红箭-73，没有激光测距")
    check(m2.weapons[1] == "m242" and has(m2.weapons, "tow1") and m2a2.weapons[1] == "m242" and has(m2a2.weapons, "tow2") and not WD.WPN.tow1.tandem
      and not m2.lrf and not m2a2.lrf and VD.get("m2a3").lrf,
      "M2 / M2A2：M242 25 毫米，M2 打单装药的改进型陶式、M2A2 打陶式 2；ISU 没有激光测距（M2A3 有）")
    -- 11-27 审查（年代错位 e）：M2A3 原来是 30 毫米 ac30——真车同样是 M242，穿甲弹换成 M919 贫铀长杆
    local m2a3 = VD.get("m2a3")
    local w3, w1 = VD.W[m2a3.weapons[1]], VD.W.m242
    check(m2a3.weapons[1] == "m242m919" and not has(m2a3.weapons, "ac30") and has(m2a3.weapons, "tow2") and WD.WPN.m242m919 ~= nil
      and pen0("m2a3") > pen0("m2a2") and w3.rate == w1.rate and w3.mag == w1.mag and w3.reserve == w1.reserve and w3.speed > w1.speed,
      string.format("M2A3：M242 25 毫米 + M919（穿深 %d > M791 %d 毫米，出膛 %.0f 格/秒），射速、载弹同 M2 / M2A2", pen0("m2a3"), pen0("m2a2"), w3.speed))
    -- 二审：M791 原来每公里掉 16（2 公里 44 毫米），M919 照战雷——2 公里处 M2A3 比 M2A2 强 64%（战雷约 32%）；M791 也照战雷（1 公里 66～67、2 公里 55～56）
    local p1, p2, q2 = WD.pen(VD.W.m242, 1000), WD.pen(VD.W.m242, 2000), WD.pen(VD.W.m242m919, 2000)
    check(math.abs(p1 - 66) <= 1.5 and math.abs(p2 - 55.5) <= 1.5 and q2 / p2 > 1.2 and q2 / p2 < 1.45,
      string.format("M791：1 公里 %.0f、2 公里 %.0f 毫米（照战雷）；2 公里处 M919 %.0f，强 %.0f%%", p1, p2, q2, (q2 / p2 - 1) * 100))
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

print("⑦ 弹种顺序（审查第 3 条）：{ 原厂穿甲, 破甲 / 多用途, 榴弹 / MPAT / 霰弹, 旧穿甲…, 射流 }——科技树只研究得到第二、第三种")
do
  -- 照真车改的这几门（原来第二种是同族更老的穿甲弹：研究「第二种弹」反而拿到一发更弱的）；科技树 M1A1 的第三种 M829A1 照真车留着（1988 年的升级弹）
  local WANT = {
    gun105m1 = "m774,m456,m735,jet105", gun105ip = "m833,m456,m774,jet105", gun120a1 = "m829,m830,m829a1,jet120",
    gun120hc = "m829a1,m830,m829,jet120", gun120a2 = "m829a1,m830,m830a1,jet120", gun120sep = "m829a2,m830,m830a1,jet120",
    gun120sep3 = "m829a4,m830a1,m1028,m829a3,jet120",
    gun105m60r = "m735,m456,jet105",   -- 二审：同 M60 / M60A1 / M60A3 三种弹、射流第三种研究得到（原来第三种 M392、射流第四：研究满拿不到）
  }
  for wid, s in pairs(WANT) do
    local got = table.concat(B.GUN[wid] or {}, ",")
    check(got == s, wid .. "：" .. got .. (got == s and "" or ("（应为 " .. s .. "）")))
  end
  -- 通则：拆出来的每一型（坦克炮）第一种是穿甲弹、第二种是聚能装药（破甲 / 多用途）、射流弹在最后；第三种以后的穿甲弹不比原厂的强（科技树 M1A1 除外，见上）
  local bad = {}
  for _, s in ipairs(SPLIT) do
    local d = VD.get(s[2])
    local list = d and d.cat == "tank" and B.GUN[d.weapons[1]]
    if list then
      local a1, a2 = B.AMMO[list[1]], B.AMMO[list[2] or ""]
      if not (a1 and a1.cls == "ap") then table.insert(bad, s[2] .. " 第一种不是穿甲弹") end
      if not (a2 and a2.ce and a2.cls ~= "jet") then table.insert(bad, s[2] .. " 第二种 " .. tostring(list[2]) .. " 不是破甲 / 多用途") end
      if not list[#list]:match("^jet") then table.insert(bad, s[2] .. " 射流弹不在最后") end
      for i = 3, #list do
        local a = B.AMMO[list[i]]
        if a and a.cls == "ap" and s[2] ~= "m1a1base" and (WD.AMMO[list[i]].p0 or 0) > (WD.AMMO[list[1]].p0 or 0) then
          table.insert(bad, s[2] .. " 第 " .. i .. " 种 " .. list[i] .. " 比原厂弹还强")
        end
      end
    end
  end
  check(#bad == 0, "拆出来的坦克炮都照这个顺序" .. (#bad > 0 and ("：" .. table.concat(bad, "；")) or ""))
end
-- 车里炮长面板的弹种键（Ballistics.panelAmmo；面板上写死的是 SEPv2 那几发：M829A3 / M830 / M830A1 / M1028）：在这门炮现在能打的弹
--   （Drive 按研究过的 ModAmmo 截短的那份）里挑同一类的，一种都没有返回 nil（按了不换）——二审：原来退回写死的那发、Drive 不认就轮到下一种，
--   SEPv3 研究了第二种弹，在 M829A4 上按 SABOT 换成了 M830A1（车里真按键的在 fponly.lua ④）
do
  local function pa(kind, wid, n, cur)
    local list = B.GUN[wid]
    local cut = {}
    for i = 1, math.min(n or #list, #list) do cut[i] = list[i] end
    return B.panelAmmo(kind, wid, cut, cur)
  end
  check(pa("SABOT", "gun120sep3", 2, "m829a4") == "m829a4" and pa("HEAT", "gun120sep3", 2) == nil and pa("MPAT", "gun120sep3", 2) == "m830a1"
    and pa("CAN", "gun120sep3", 2) == nil and pa("CAN", "gun120sep3", 3) == "m1028",
    "面板 · SEPv3 研究了第二种弹：SABOT 还是 M829A4（M829A3 排第四研究不到）、HEAT 不换（没有破甲弹）、MPAT → M830A1、CAN 研究了第三种才有")
  check(pa("SABOT", "gun105m1", 3, "m456") == "m774" and pa("HEAT", "gun105m1", 3) == "m456" and pa("MPAT", "gun105m1", 3) == nil and pa("CAN", "gun105m1", 3) == nil,
    "面板 · M1（105 毫米）：SABOT → M774、HEAT → M456，MPAT / CAN 不换（这门炮没有）")
  check(pa("SABOT", "gun120a1", 3, "m830") == "m829" and pa("SABOT", "gun120a1", 3, "m829") == "m829a1" and pa("SABOT", "gun120a1", 3, "m829a1") == "m829"
    and pa("SABOT", "gun120a1", 1, "m829") == "m829",
    "面板 · 科技树 M1A1：SABOT 先选 M829，已经是 M829 再按换第三种 M829A1（研究了才有）")
  check(pa("SABOT", "gun120") == "m829a3" and pa("HEAT", "gun120") == "m830" and pa("MPAT", "gun120") == "m830a1" and pa("CAN", "gun120") == "m1028"
    and pa("ap", "gun125r") == "bm60" and pa("heat", "gun125r") == "bk31" and pa("he", "gun125r") == "of26" and pa("ap", "gun125") == "dtc10",
    "面板 · SEPv2 四个键各对一种；T-90M 借 99A 的面板：穿甲 3BM60、破甲 3BK31、榴弹 3OF26")
end

print("⑧ 年代错位、拟真修正")
do
  -- a. 爆反挡导弹按装药（Era.lua G.eraBlast 用 WtDamage.singleCharge）：单装药的按 k（同火箭弹），串联的按 kt；按种类给的通用表项（飞机的空地导弹）照旧按串联
  local SINGLE = { "tow1", "hj73", "malyutka", "konkurs" }
  local TANDEM = { "tow2", "kornet" }
  local ok1 = true
  for _, wid in ipairs(SINGLE) do if not WD.singleCharge(VD.W[wid]) then ok1 = false end end
  for _, wid in ipairs(TANDEM) do if WD.singleCharge(VD.W[wid]) then ok1 = false end end
  local refl = { ammo = "refleks", kind = "shell", base = VD.W.gun125r }   -- 炮射导弹「反射」（服务器开火时的武器表：炮的那份 + ammo）
  check(ok1 and not WD.singleCharge(refl) and not WD.singleCharge({ kind = "agm" }) and not WD.singleCharge({ kind = "missile" })
    and not WD.singleCharge(VD.W.s57e6) and not WD.singleCharge(VD.W.gun125),
    "单装药：陶式 1、红箭-73、「婴儿」、「竞技」；串联：陶式 2、「短号」、「反射」；空地导弹、地空导弹、炮弹都不算单装药")
  -- b. 59 / 69 式的剪影：HudIcons 原来生成成 veh_veh_type59（hudicons.py 给已经带 veh_ 的图名又加了一遍），驾驶界面查不到
  local veh2 = {}
  for k in pairs(hudKeys) do if k:match("^veh_veh_") then table.insert(veh2, k) end end
  check(hudKeys.veh_type59 and #veh2 == 0 and VD.get("type69").like == "type59",
    "59 式有剪影（veh_type59），69-II 式退到 59 式（like）；没有 veh_veh_ 开头的键" .. (#veh2 > 0 and ("：" .. table.concat(veh2, " ")) or ""))
  -- 驾驶界面（VehHud）、召唤卡片（Depot）按 veh_<型号>、再 veh_<like> 找：科技树每一辆地面车都要找得到（KNOWN：还没拍过的，回报里写）
  local KNOWN = { brdm2 = true, strela1 = true, type87rcv = true }   -- 11-27 E 补的三型：vehicons.mjs 的 GLB 表里有，HudIcons 还没重拍
  local miss, known = {}, {}
  for _, nat in ipairs(TT.NATIONS) do
    for _, it in ipairs(TT.list[nat].ground) do
      local d = VD.get(it.play)
      local found = d and (hudKeys["veh_" .. d.id] or (d.like and hudKeys["veh_" .. d.like]))
      if not found then table.insert(KNOWN[it.play] and known or miss, it.key .. "（" .. tostring(it.play) .. "）") end
    end
  end
  check(#miss == 0, "科技树的地面车都有驾驶界面的剪影（自己的或 like 的）" .. (#miss > 0 and ("：缺 " .. table.concat(miss, " ")) or "")
    .. (#known > 0 and ("；还没拍的老问题：" .. table.concat(known, " ")) or ""))
  -- c. 火控代见 ⑤（M60、M60A1 第 1 代）
  -- d. 没有稳定器的：M60（1960）、59 式、豹 1 头一批（1965）；从它们拷出来、真车有稳定器的变型写了 noStab = false
  local leo1, l1a1, l1a5, t59, t69 = VD.get("leo1"), VD.get("leo1a1a1"), VD.get("leo1a5"), VD.get("type59"), VD.get("type69")
  -- 1962 年的 M60A1 不在这里锁（见 ⑤：真车 AOS 稳定器 1972 年才有，照 1962 还是照战雷 M60A1 (AOS) 要用户定）
  check(TT.get("de_leo1").play == "leo1" and TT.get("de_leo1").year == 1965 and leo1.noStab == true and t59.noStab == true and VD.get("m60").noStab == true
    and not l1a1.noStab and not l1a5.noStab and not t69.noStab and not VD.get("m60a1rise").noStab and not VD.get("m60a3").noStab
    and not VD.get("gepard1a1").noStab,
    "没有稳定器：59 式、豹 1（1965 年头一批）、M60；69-II、豹 1A1A1、豹 1A5、M60A1 RISE、M60A3 有")
end

local dt = os.clock() - t0
check(dt < 1.5, string.format("跑了 %.2f 秒（不开服）", dt))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
