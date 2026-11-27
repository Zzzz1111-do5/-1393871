-- 全面大战场——科技树每辆车的改装（用户 11-25「都要做」：照战雷那样，车买来是「原厂」状态，打仗挣研究点一项项研究改装）
--   这辆车打仗挣的研究点先给它正在研究的那项改装（Tech.lua G.treeAward；没选就自动挑下一项），研究完自动装上、效果真的生效：
--   地面车：
--     机动——履带（转向快）、悬挂（加速、转向）、空滤（极速、加速）、传动（加速）、发动机（极速、加速）：
--       车上的 ModSpd / ModAcc / ModTurn 属性，客户端 Drive.lua 开车时乘（服务器按型号车速的 1.5 倍限移动，加的这点不会被拉回）
--     防护——零件（没研究：坏了的模块修不了，Wt.lua wtFix）、灭火器（没研究：着火只能等它烧完，wtExt）、
--       烟幕弹（没研究：车上没烟幕弹）、工具箱（修车快四分之一）
--     火力——炮塔驱动（炮塔转得快：ModTrav）、第二种弹 / 第三种弹（没研究只能打第一种：服务器 Armor.lua 按 ModAmmo 认，客户端换弹也跳过）
--   飞机：散热器 / 压缩机 / 发动机 / 新发动机（推力：ModThr，客户端 Fly.lua 乘）、机身 / 机翼 / 座舱装甲（血量）、
--     干扰弹（没研究：没有热焰弹）
--   每一级研究完 TIER_NEED 项开下一级；价钱按这辆车的级别（越新越贵）
--   火控计算机（用户 11-25「科技树里面根据年代给有火控计算机的坦克 在坦克细分具体小科技的树里面更新火控计算机 可以有不同等级进行升级」）：
--     有坦克炮的车按年代定原厂火控是哪一代（M.FCS：光学测距 + 机械计算机 → 激光 + 模拟计算机 → 数字火控 → 猎歼式自动跟踪），
--     改装树「火力」一栏多三项火控升级（测距 → 弹道传感器 → 数字火控），客户端 Drive.lua 开镜瞄准按它（测距多久、误差、
--     解算多久、提前量怎么算、残余散布、自动跟踪）；服务器 Tech.lua 写车上的 FcsGen / ModFcs
local M = {}
local RS = game:GetService("ReplicatedStorage")
local VD = require(RS:WaitForChild("VehDefs"))
local BAL = require(RS:WaitForChild("Ballistics"))

M.CLS = { "mob", "pro", "fire" }
M.CLS_NAME = { mob = { "机动", "Mobility" }, pro = { "防护", "Protection" }, fire = { "火力", "Firepower" } }
M.TIER_NEED = 2
M.BASE = { 1200, 1800, 2400, 3000 }   -- 第一级车每级改装多少研究点（整套约 2.5 万，一局打得好挣五六千：四五局装齐）；车每高一级 × 1.5

-- fx：效果（下面 M.fx 合起来）；desc：界面上写的（和效果一致）
M.GROUND = {
  { key = "tracks", cls = "mob", tier = 1, zh = "履带", en = "Tracks", fx = { turn = 1.06 }, dz = "转向快 6%", de = "Turning +6%" },
  { key = "parts", cls = "pro", tier = 1, zh = "零件", en = "Parts", fx = { repair = true }, dz = "能在战场上修坏了的模块（没有它坏了就修不了）", de = "Repair damaged modules in battle" },
  { key = "ammo2", cls = "fire", tier = 1, zh = "第二种弹", en = "2nd ammo type", fx = { ammo = 2 }, dz = "解锁这门炮的第二种弹", de = "Unlocks the gun's 2nd shell" },
  { key = "susp", cls = "mob", tier = 2, zh = "悬挂", en = "Suspension", fx = { accel = 1.05, turn = 1.04 }, dz = "加速快 5%、转向快 4%", de = "Accel +5%, turning +4%" },
  { key = "fpe", cls = "pro", tier = 2, zh = "灭火器", en = "FPE", fx = { ext = true }, dz = "着火能自己扑灭（没有它只能等火烧完）", de = "Put out fires yourself" },
  { key = "hdrive", cls = "fire", tier = 2, zh = "炮塔驱动", en = "Horizontal drive", fx = { trav = 1.15 }, dz = "炮塔转得快 15%", de = "Turret traverse +15%" },
  { key = "filter", cls = "mob", tier = 3, zh = "空滤", en = "Filters", fx = { speed = 1.03, accel = 1.05 }, dz = "极速 +3%、加速快 5%", de = "Top speed +3%, accel +5%" },
  { key = "smoke", cls = "pro", tier = 3, zh = "烟幕弹", en = "Smoke grenades", fx = { smoke = true }, dz = "车上装烟幕弹发射器", de = "Smoke grenade launchers" },
  { key = "ammo3", cls = "fire", tier = 3, zh = "第三种弹", en = "3rd ammo type", fx = { ammo = 3 }, dz = "解锁这门炮的第三种弹", de = "Unlocks the gun's 3rd shell" },
  { key = "trans", cls = "mob", tier = 4, zh = "传动", en = "Transmission", fx = { accel = 1.08, speed = 1.02 }, dz = "加速快 8%、极速 +2%", de = "Accel +8%, top speed +2%" },
  { key = "engine", cls = "mob", tier = 4, zh = "发动机", en = "Engine", fx = { speed = 1.06, accel = 1.1 }, dz = "极速 +6%、加速快 10%", de = "Top speed +6%, accel +10%" },
  { key = "tools", cls = "pro", tier = 4, zh = "工具箱", en = "Improved parts", fx = { repK = 0.75 }, dz = "修车快四分之一", de = "Repairs 25% faster" },
}
M.AIR = {
  { key = "rad", cls = "mob", tier = 1, zh = "散热器", en = "Radiator", fx = { thr = 1.02 }, dz = "推力 +2%", de = "Thrust +2%" },
  { key = "fuse", cls = "pro", tier = 1, zh = "机身修理", en = "Fuselage repair", fx = { hp = 1.05 }, dz = "机身血量 +5%", de = "Airframe HP +5%" },
  { key = "comp", cls = "mob", tier = 2, zh = "压缩机", en = "Compressor", fx = { thr = 1.03 }, dz = "推力 +3%", de = "Thrust +3%" },
  { key = "wing", cls = "pro", tier = 2, zh = "机翼修理", en = "Wings repair", fx = { hp = 1.05 }, dz = "机身血量 +5%", de = "Airframe HP +5%" },
  { key = "engine", cls = "mob", tier = 3, zh = "发动机", en = "Engine", fx = { thr = 1.05 }, dz = "推力 +5%", de = "Thrust +5%" },
  { key = "flares", cls = "pro", tier = 3, zh = "干扰弹", en = "Countermeasures", fx = { flares = true }, dz = "带热焰弹（没有它挂不了）", de = "Carry flares" },
  { key = "neweng", cls = "mob", tier = 4, zh = "新发动机", en = "New engines", fx = { thr = 1.04 }, dz = "推力 +4%", de = "Thrust +4%" },
  { key = "cover", cls = "pro", tier = 4, zh = "座舱装甲", en = "Cockpit armor", fx = { hp = 1.05 }, dz = "机身血量 +5%", de = "Airframe HP +5%" },
}

-- 火控的几代（真车的参数取个大概）：rangeT 测距要多久（秒；没有激光的是车长估距 / 合像测距仪对焦）、err 测距误差（比例）、
--   solve 弹道计算机出结果要多久、lead 提前量（0 没有、1 测距那一下按跟踪角速度算、2 随时算 = 动态提前量）、
--   sig 残余散布（密位：弹道表、横风、炮耳倾斜没修正的）、track 自动目标跟踪（测距锁住车，瞄准线自己跟着它）
M.FCS = {
  [0] = { zh = "光学瞄准镜（分划估距）", en = "Optical sight (stadia ranging)", rangeT = 2.6, err = 0.1, solve = 0, lead = 0, sig = 0.6 },
  [1] = { zh = "光学测距仪 + 机械弹道计算机", en = "Optical rangefinder + mechanical computer", rangeT = 2.0, err = 0.05, solve = 1.0, lead = 0, sig = 0.45 },
  [2] = { zh = "激光测距 + 模拟弹道计算机", en = "Laser rangefinder + analog computer", rangeT = 0.35, err = 0, solve = 0.6, lead = 1, sig = 0.3 },
  [3] = { zh = "数字火控 + 热像仪", en = "Digital FCS + thermal sight", rangeT = 0.2, err = 0, solve = 0.25, lead = 2, sig = 0.18 },
  [4] = { zh = "猎歼式数字火控（自动目标跟踪）", en = "Hunter-killer digital FCS (auto-tracker)", rangeT = 0.12, err = 0, solve = 0.1, lead = 2, sig = 0.12, track = true },
}
-- 原厂火控是哪一代：按年份（1965 年以前没有火控计算机，1978 年以后激光 + 计算机，1992 年以后数字火控，2006 年以后猎歼式）；
--   没有激光测距机的（豹 1、M60A1、BMP-1、T-64A）最多第一代；步战车没有猎歼式；没有坦克炮的（防空车、导弹车）nil
-- 按年份推错的：T-64B（1976）已经是 1G21 激光测距 + 1V517 弹道计算机（1A33 火控），74 式（1975）有红宝石激光测距 + 模拟弹道计算机——都是激光一代（2），
--   按年份会落到光学（1）（11-27 梳理瞄准镜时查出来的）
--   11-27 拆开重叠的版本：M1A2（1992）、M1A2 SEP（2000）有车长独立热像仪（CITV），是猎歼式（4），按年份会落到数字火控（3）
M.GEN_FIX = { ru_t64b = 2, jp_type74 = 2, us_m1a2 = 4, us_m1a2sep = 4 }
function M.fcsGen(it)
  if not it or it.branch ~= "ground" then return nil end
  local d = VD.get(it.play or "")
  if not d or not d.weapons then return nil end
  local gun = false
  for _, w in ipairs(d.weapons) do if BAL.GUN[w] then gun = true break end end
  if not gun then return nil end
  local y = it.year or 2000
  local g = (y < 1965 and 0) or (y < 1978 and 1) or (y < 1992 and 2) or (y < 2006 and 3) or 4
  if M.GEN_FIX[it.key or ""] then g = M.GEN_FIX[it.key] end   -- 按年份推不对的几型（真车资料）
  if d.lrf == false then g = math.min(g, 1) end
  if d.cat ~= "tank" then g = math.min(g, 3) end
  return g
end
-- 原厂这一代 + 升级了几项 → 客户端用的参数
function M.fcsParams(gen, lvl)
  local B = M.FCS[gen or 2] or M.FCS[2]
  local P = table.clone(B)
  lvl = lvl or 0
  if lvl >= 1 then P.rangeT = P.rangeT * 0.6 P.err = P.err * 0.5 end   -- 测距：快四成、误差减半
  if lvl >= 2 then P.sig = P.sig * 0.6 P.solve = P.solve * 0.5 end   -- 弹道传感器（横风、药温、炮耳倾斜）：散布少四成、解算快一倍
  if lvl >= 3 then   -- 数字火控：提前量升一档；原厂已经是数字火控的再加自动目标跟踪
    P.lead = math.min(2, P.lead + 1)
    if gen and gen >= 3 then P.track = true end
  end
  return P
end
-- 火控升级三项（只有有火控计算机的车才有：原厂第一代以上）；说明按这辆车原厂是哪一代写
local function fcsItems(gen)
  local function L3()
    if gen <= 1 then return "加角速度传感器：测距那一下自动算提前量", "Rate sensors: lead computed when ranging" end
    if gen == 2 then return "提前量随时算（动态提前量），不用测距那一刻对准", "Dynamic lead: lead updated continuously" end
    return "动态提前量 + 自动目标跟踪：测距锁住目标，瞄准线自己跟着它（动鼠标解除）", "Dynamic lead + auto-tracker: ranging locks the target and the sight follows it"
  end
  local z3, e3 = L3()
  return {
    { key = "fcs1", cls = "fire", tier = 2, zh = "火控 I · 测距", en = "FCS I · Ranging", fx = { fcs = 1 },
      dz = (gen <= 1) and "测距快 40%、估距误差减半" or "激光测距、出结果快 40%", de = (gen <= 1) and "Ranging 40% faster, error halved" or "Laser ranging 40% faster" },
    { key = "fcs2", cls = "fire", tier = 3, zh = "火控 II · 弹道传感器", en = "FCS II · Ballistic sensors", fx = { fcs = 2 },
      dz = "横风、药温、炮耳倾斜传感器：散布少 40%、弹道解算快一倍", de = "Crosswind / temperature / cant sensors: −40% dispersion, 2× faster solution" },
    { key = "fcs3", cls = "fire", tier = 4, zh = "火控 III · 数字火控", en = "FCS III · Digital FCS", fx = { fcs = 3 }, dz = z3, de = e3 },
  }
end
local listCache = {}
function M.list(it)
  if it and (it.branch == "air" or it.branch == "heli") then return M.AIR end   -- 直升机用飞机那套改装
  local gen = it and M.fcsGen(it)
  if not gen or gen < 1 then return M.GROUND end
  local c = listCache[it.key]
  if c then return c end
  c = table.clone(M.GROUND)
  for _, m in ipairs(fcsItems(gen)) do table.insert(c, m) end
  listCache[it.key] = c
  return c
end
function M.get(it, key)
  for _, m in ipairs(M.list(it)) do if m.key == key then return m end end
  return nil
end
function M.cost(it, m)
  local base = M.BASE[m.tier] or 1000
  return math.floor(base * (1 + 0.5 * (((it and it.rank) or 1) - 1)) / 50 + 0.5) * 50
end
-- 这一级开了没有：上一级研究完 TIER_NEED 项
function M.tierOpen(it, done, tier)
  if tier <= 1 then return true end
  local n = 0
  for _, m in ipairs(M.list(it)) do
    if m.tier == tier - 1 and done and done[m.key] then n += 1 end
  end
  return n >= M.TIER_NEED
end
function M.canResearch(it, done, key)
  local m = M.get(it, key)
  if not m or (done and done[key]) then return false end
  return M.tierOpen(it, done, m.tier)
end
-- 下一项（没选研究目标时自动挑）：级别低的先，同一级按机动、防护、火力
function M.nextKey(it, done)
  for tier = 1, 4 do
    for _, c in ipairs(M.CLS) do
      for _, m in ipairs(M.list(it)) do
        if m.tier == tier and m.cls == c and not (done and done[m.key]) and M.tierOpen(it, done, tier) then return m.key end
      end
    end
  end
  return nil
end
function M.count(it, done)
  local n, all = 0, 0
  for _, m in ipairs(M.list(it)) do
    all += 1
    if done and done[m.key] then n += 1 end
  end
  return n, all
end
-- 装了的改装合起来的效果：倍率相乘，开关有一个就算；ammo 能打前几种弹（原厂只有第一种）
function M.fx(it, done)
  local f = { speed = 1, accel = 1, turn = 1, trav = 1, repK = 1, thr = 1, hp = 1, ammo = 1, repair = false, ext = false, smoke = false, flares = false,
    fcs = 0, gen = M.fcsGen(it) }   -- fcs 火控升级了几级、gen 原厂火控是哪一代（没有坦克炮的 nil）
  for _, m in ipairs(M.list(it)) do
    if done and done[m.key] then
      for k, v in pairs(m.fx) do
        if type(v) == "boolean" then f[k] = f[k] or v
        elseif k == "ammo" or k == "fcs" then f[k] = math.max(f[k], v)
        else f[k] = (f[k] or 1) * v end
      end
    end
  end
  return f
end

return M
