-- Roblox全面大战场——改枪（用户 11-20：「做一整套改枪系统，对标三角洲行动」；服务器、客户端共用）
--   每把枪几个改装位：枪口、瞄具、前握把、弹匣、战术（狙击枪只有枪口）；每个位几样配件，配件是 Sketchfab 上 CC-BY 的原模型
--   （tools/weapons/optics.json → OpticsMeta / OpticMesh / models/optics/<键>.glb），第一人称、第三人称、改枪界面装的都是它
--   性能照三角洲那几项「分」（0～100）：垂直 / 水平后坐力控制、操控速度、据枪稳定性、腰际射击精度、有效射程、机动性——
--     配件按分加减，GM.apply 把分换成真正起作用的数（后坐、开镜快慢、晃动、散布、射程、走路速度），另外弹匣改容量和换弹时间、
--     消音器开枪不上敌人雷达（服务器本来就按 w.quiet）、换声音、没有枪口焰，激光提高腰射精度（别人看得见那道光），手电照亮前面
--   服务器（Weapons.lua）开枪、换弹、射程、散布、伤害衰减按 GM.apply 算出的那份；客户端（Play、FPSView、Fx 的后坐、Scope）用同一份
--   枪械等级：用这把枪打死人加经验（Config.GunMods.killXp），升级解锁配件（每把枪的 slots 里写了几级解锁）；
--     Config.GunMods.unlockAll 全部解锁，studioAll 在 Studio 里测试时全部解锁
--   改枪码：枪名-版本 + 配件编码 + 两位校验（base32），例如 M4A1-100C2K；复制给别人，粘贴进改枪界面就装上
--   工具属性 Build（服务器发枪时写）："muzzle=sup_socom;optic=opt_holo;..."（GM.encode / GM.decode），大家的客户端照它装配件
local GM = {}

GM.SLOTS = { "muzzle", "optic", "grip", "mag", "tac" }
-- 性能分（三角洲那几项）；界面上按这个顺序排
GM.STATS = { "vrec", "hrec", "hand", "stab", "hip", "range", "mob" }

-- 配件：slot 哪个位，model 模型键（OpticsMeta；没有的是枪本身带的 / 不装），st 加减几分，
--   quiet 消音、zoom 开镜倍率、scope 光学镜（开镜后屏幕上是目镜里的像，Scope.lua 的种类）、dot 反射式瞄具的分划（dot 红点 / holo 全息圈）、
--   mag 弹匣容量、reload 换弹时间倍数、laser 激光指示器、light 战术手电
GM.ITEM = {
  -- 枪口
  fh_a2 = { slot = "muzzle" },                                                                         -- M4 原装 A2 消焰器（枪身模型自带）
  muz_none = { slot = "muzzle" },                                                                      -- 狙击枪原装枪口
  muz_comp = { slot = "muzzle", model = "muz_comp", st = { vrec = 10, hrec = 3, hand = -2 } },          -- 战术补偿器：往上喷气压枪口
  muz_brake = { slot = "muzzle", model = "muz_brake", st = { hrec = 12, vrec = 5, hand = -3, stab = -2 } },   -- 多孔制退器：左右飘得少
  sup_socom = { slot = "muzzle", model = "sup_socom", quiet = true, st = { vrec = 5, hrec = 5, hand = -7, stab = -2 } },
  sup_wrap = { slot = "muzzle", model = "sup_wrap", quiet = true, st = { vrec = 3, hrec = 8, hand = -5, range = -6 } },
  sup_sr8 = { slot = "muzzle", model = "sup_sr8", quiet = true, st = { range = 12, vrec = 8, hrec = 4, hand = -12, mob = -2 } },
  -- 瞄具
  iron = { slot = "optic", zoom = 1.3, st = { hand = 5 } },                                              -- 机械瞄具（枪身自带的照门、准星）
  --   glass 镜片 / 窗玻璃的块和它的透明度（开镜时不挡眼睛；全息原模型窗上画着的分划整块藏掉，屏幕上另画）；
  --   eye / obj 光轴（器材坐标、半径，原模型量的）；adsD 开镜时后窗离眼睛多远（格：小的凑近一点、大的离远一点，窗口在屏幕上差不多大）
  opt_romeo = { slot = "optic", model = "opt_romeo", zoom = 1.35, dot = "dot", riser = 0.08, adsD = 0.22, st = { hand = 3 },
    glass = { Body = 0.86, Body2 = 0.86, Body3 = 0.86, C022 = 0.86 } },
  opt_rds = { slot = "optic", model = "opt_rds", zoom = 1.45, dot = "dot", adsD = 0.3, st = { hand = -1, stab = 2 },
    glass = { Body2 = 0.86 }, eye = { 0.037, 0.153, -0.191, 0.069 }, obj = { 0.037, 0.153, 0.192, 0.071 } },
  opt_holo = { slot = "optic", model = "opt_holo", zoom = 1.5, dot = "holo", adsD = 0.45, st = { hand = -2, stab = 2, hip = 3 },
    glass = { Body2 = 0.86, Body4 = 1 } },
  --   lensK：开镜时目镜（正圆的洞）在屏幕上占高度的几成——使命召唤那样外面围着一圈目镜、镜身（两具 ACOG 的原模型目镜是八边形的，
  --     tools/weapons/optics.json 的 ring 补了正圆的目镜圈罩住；目镜 / 物镜的位置、洞的半径在 OpticsMeta 里）
  --   镜片（glass）半透明：腰射、举镜时从后面看得穿（开镜时整块藏掉，从目镜的洞里直接看放大的画面）
  --   pipK：镜内单独放大（画中画，ScopePip.lua）时目镜占屏高——镜外只是普通开镜，目镜离眼睛近一点（再近会被镜头的近裁剪面切掉）
  acog = { slot = "optic", model = "acog", zoom = 3.5, scope = "acog", lensK = 0.5, pipK = 0.3, st = { hand = -7, stab = 4 }, glass = { GlassIn = 0.62 } },
  opt_acog6 = { slot = "optic", model = "opt_acog6", zoom = 6, scope = "acog6", lensK = 0.55, pipK = 0.36, st = { hand = -12, stab = 6, mob = -1 },
    glass = { C9ab = 0.62, C9abIn = 0.62 } },
  -- 前握把
  grip_none = { slot = "grip" },
  grip_rvg = { slot = "grip", model = "grip_rvg", st = { vrec = 8, stab = 5, hand = -3 } },
  grip_afg = { slot = "grip", model = "grip_afg", st = { hand = 7, hrec = 5, vrec = 2 } },
  -- 弹匣
  mag_std = { slot = "mag", mag = 30 },                                                                -- 原装 30 发（枪身模型自带）
  mag_pmag20 = { slot = "mag", model = "mag_pmag20", mag = 20, reload = 0.85, st = { hand = 4, mob = 2 } },
  mag_hex30 = { slot = "mag", model = "mag_hex30", mag = 30, reload = 0.92, st = { hand = 1 } },
  mag_pmag40 = { slot = "mag", model = "mag_pmag40", mag = 40, reload = 1.12, st = { hand = -4, mob = -1 } },
  mag_drum = { slot = "mag", model = "mag_drum", mag = 60, reload = 1.4, st = { hand = -10, mob = -4, stab = 2 } },
  -- 战术
  tac_none = { slot = "tac" },
  tac_light = { slot = "tac", model = "tac_light", light = true, st = { hip = 5 } },
  tac_peq = { slot = "tac", model = "tac_peq", laser = true, st = { hip = 16, hand = -1 } },
}

-- 每把枪：tag 改枪码前缀，base 裸枪（机械瞄具、原装枪口和弹匣、不装握把战术）的分，slots 每个位能装的 { 配件, 几级解锁 }（第一个是裸枪的），
--   def 默认装的（M4 原来就带一具 ACOG：照旧），presets 推荐改装（三角洲那样一键套用）
GM.DEF = {
  m4 = {
    tag = "M4A1",
    base = { vrec = 52, hrec = 58, hand = 60, stab = 55, hip = 48, range = 46, mob = 72 },
    slots = {
      muzzle = { { "fh_a2", 1 }, { "muz_comp", 2 }, { "muz_brake", 5 }, { "sup_socom", 7 }, { "sup_wrap", 10 }, { "sup_sr8", 13 } },
      optic = { { "iron", 1 }, { "opt_romeo", 1 }, { "acog", 1 }, { "opt_rds", 3 }, { "opt_holo", 6 }, { "opt_acog6", 11 } },
      grip = { { "grip_none", 1 }, { "grip_rvg", 2 }, { "grip_afg", 8 } },
      mag = { { "mag_std", 1 }, { "mag_pmag20", 3 }, { "mag_hex30", 4 }, { "mag_pmag40", 9 }, { "mag_drum", 14 } },
      tac = { { "tac_none", 1 }, { "tac_light", 4 }, { "tac_peq", 12 } },
    },
    def = { muzzle = "fh_a2", optic = "acog", grip = "grip_none", mag = "mag_std", tac = "tac_none" },
    presets = {
      { id = "cqb", b = { muzzle = "muz_brake", optic = "opt_holo", grip = "grip_afg", mag = "mag_pmag40", tac = "tac_peq" } },
      { id = "all", b = { muzzle = "muz_comp", optic = "acog", grip = "grip_rvg", mag = "mag_hex30", tac = "tac_light" } },
      { id = "stealth", b = { muzzle = "sup_socom", optic = "opt_rds", grip = "grip_afg", mag = "mag_std", tac = "tac_none" } },
      { id = "lmg", b = { muzzle = "muz_comp", optic = "opt_holo", grip = "grip_rvg", mag = "mag_drum", tac = "tac_peq" } },
      { id = "dmr", b = { muzzle = "sup_sr8", optic = "opt_acog6", grip = "grip_rvg", mag = "mag_pmag20", tac = "tac_none" } },
    },
  },
  sniper = {
    tag = "SR",
    base = { vrec = 28, hrec = 46, hand = 38, stab = 64, hip = 12, range = 92, mob = 60 },
    slots = {
      muzzle = { { "muz_none", 1 }, { "muz_brake", 2 }, { "sup_sr8", 4 } },
    },
    def = { muzzle = "muz_none" },
    presets = {
      { id = "std", b = { muzzle = "muz_none" } },
      { id = "stable", b = { muzzle = "muz_brake" } },
      { id = "stealth", b = { muzzle = "sup_sr8" } },
    },
  },
}

-- 枪械等级：到第 i 级要累计多少经验（满级 = 表长）；每把枪最多到 maxLv
GM.XP = { 0, 200, 500, 900, 1400, 2000, 2700, 3500, 4400, 5400, 6500, 7700, 9000, 10400, 12000 }
GM.DEF.m4.maxLv = 15
GM.DEF.sniper.maxLv = 5

-- 性能分 → 真正的数：每分改多少（后坐、散布、晃动 1.2%，开镜快慢 1.2%，射程 1%，走路速度 0.4%）
local K_REC, K_HIP, K_STAB, K_HAND, K_RANGE, K_MOB = 0.012, 0.012, 0.012, 0.012, 0.01, 0.004
local RC0 = { up = 0.3, side = 0.12, punch = 1.0, roll = 0.5 }   -- 没写 rc 的枪按 M4 的

local function find(list, id)
  for i, x in ipairs(list) do if x[1] == id then return i, x end end
  return nil
end
GM.find = find

function GM.has(id) return GM.DEF[id] ~= nil end

-- 选的配件（表）整理成合法的：没选的、这把枪装不了的用默认；lv 给了的话，没解锁的也换成默认（all = true 全部解锁）
function GM.clean(id, b, lv, all)
  local D = GM.DEF[id]
  if not D then return nil end
  local out = {}
  for _, slot in ipairs(GM.SLOTS) do
    local list = D.slots[slot]
    if list then
      local want = type(b) == "table" and b[slot] or nil
      local i, x = nil, nil
      if type(want) == "string" then i, x = find(list, want) end
      if x and lv and not all and x[2] > lv then x = nil end
      out[slot] = x and x[1] or D.def[slot]
    end
  end
  return out
end

function GM.default(id)
  local D = GM.DEF[id]
  return D and table.clone(D.def) or nil
end

-- 这一位的这样配件几级解锁（装不了返回 nil）
function GM.unlockLv(id, slot, item)
  local D = GM.DEF[id]
  local list = D and D.slots[slot]
  local _, x = list and find(list, item)
  return x and x[2] or nil
end

-- 经验 → 等级、这一级起点、下一级要多少（满级时 nxt 是 nil）
function GM.level(id, xp)
  local D = GM.DEF[id]
  local maxLv = (D and D.maxLv) or #GM.XP
  xp = math.max(0, tonumber(xp) or 0)
  local lv = 1
  for i = 2, maxLv do
    if xp >= GM.XP[i] then lv = i end
  end
  return lv, GM.XP[lv], (lv < maxLv) and GM.XP[lv + 1] or nil
end

-- 从 a 级升到 b 级新解锁的配件
function GM.unlocksBetween(id, a, b)
  local D = GM.DEF[id]
  local out = {}
  if not D then return out end
  for _, slot in ipairs(GM.SLOTS) do
    for _, x in ipairs(D.slots[slot] or {}) do
      if x[2] > a and x[2] <= b then table.insert(out, x[1]) end
    end
  end
  return out
end

---------------------------------------------------------------- 存、传

-- 工具属性、存档用的写法："muzzle=sup_socom;optic=opt_holo;…"
function GM.encode(b)
  if type(b) ~= "table" then return "" end
  local parts = {}
  for _, slot in ipairs(GM.SLOTS) do
    if type(b[slot]) == "string" then table.insert(parts, slot .. "=" .. b[slot]) end
  end
  return table.concat(parts, ";")
end

function GM.decode(s)
  local b = {}
  if type(s) ~= "string" then return b end
  for k, v in string.gmatch(s, "([%w_]+)=([%w_]+)") do b[k] = v end
  return b
end

-- 改枪码（分享用）：每个位在列表里的序号按混合进制拼成一个数，写成 base32（去掉容易看错的 I L O U），最后两位校验——
--   校验 = Σ（第 i 位 × i）+ 枪名的数，对 1021（质数）取余：抄错任意一位、相邻两位写反都对不上
local B32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
local B32I = {}
for i = 1, #B32 do B32I[string.sub(B32, i, i)] = i - 1 end
local VERSION = "1"

local function checksum(tag, core)
  local c = 0
  for i = 1, #tag do c = (c * 7 + string.byte(tag, i)) % 1021 end
  for i = 1, #core do c = (c + i * (B32I[string.sub(core, i, i)] or 0)) % 1021 end
  return c
end

function GM.code(id, b)
  local D = GM.DEF[id]
  if not D then return nil end
  b = GM.clean(id, b)
  local v, mul = 0, 1
  for _, slot in ipairs(GM.SLOTS) do
    local list = D.slots[slot]
    if list then
      v += ((find(list, b[slot]) or 1) - 1) * mul
      mul *= #list
    end
  end
  local s = ""
  repeat
    s = string.sub(B32, v % 32 + 1, v % 32 + 1) .. s
    v = math.floor(v / 32)
  until v == 0
  while #s < 3 do s = "0" .. s end
  local core = VERSION .. s
  local c = checksum(D.tag, core)
  local hi, lo = math.floor(c / 32), c % 32
  return D.tag .. "-" .. core .. string.sub(B32, hi + 1, hi + 1) .. string.sub(B32, lo + 1, lo + 1)
end

-- 粘贴来的改枪码 → 枪、配件表；认不出来返回 nil 和原因（"bad" 格式不对、"sum" 校验不对、"gun" 不是这几把枪的）
function GM.parse(text)
  if type(text) ~= "string" then return nil, nil, "bad" end
  local s = string.upper(string.gsub(text, "%s", ""))
  local tag, body = string.match(s, "^([%w]+)%-([%w]+)$")
  if not tag then return nil, nil, "bad" end
  body = string.gsub(string.gsub(body, "O", "0"), "[IL]", "1")   -- 手抄的：O 当 0、I / L 当 1
  local id = nil
  for k, D in pairs(GM.DEF) do if D.tag == tag then id = k end end
  if not id then return nil, nil, "gun" end
  if #body < 6 or string.sub(body, 1, 1) ~= VERSION then return nil, nil, "bad" end
  local core = string.sub(body, 1, -3)
  local hi, lo = B32I[string.sub(body, -2, -2)], B32I[string.sub(body, -1)]
  if hi == nil or lo == nil then return nil, nil, "bad" end
  for i = 1, #core do if B32I[string.sub(core, i, i)] == nil then return nil, nil, "bad" end end
  if checksum(tag, core) ~= hi * 32 + lo then return nil, nil, "sum" end
  local v = 0
  for i = 2, #core do v = v * 32 + B32I[string.sub(core, i, i)] end
  local D = GM.DEF[id]
  local b = {}
  for _, slot in ipairs(GM.SLOTS) do
    local list = D.slots[slot]
    if list then
      local n = #list
      local i = v % n
      v = math.floor(v / n)
      b[slot] = list[i + 1][1]
    end
  end
  if v ~= 0 then return nil, nil, "bad" end
  return id, b
end

---------------------------------------------------------------- 性能

-- 装上这一套以后的分（裸枪的分 + 每样配件加减的）
function GM.score(id, b)
  local D = GM.DEF[id]
  local s = {}
  if not D then return s end
  for _, k in ipairs(GM.STATS) do s[k] = D.base[k] or 50 end
  b = GM.clean(id, b)
  for _, slot in ipairs(GM.SLOTS) do
    local it = b[slot] and GM.ITEM[b[slot]]
    if it and it.st then
      for k, v in pairs(it.st) do s[k] = (s[k] or 50) + v end
    end
  end
  for k, v in pairs(s) do s[k] = math.clamp(v, 0, 100) end
  return s
end

local function kOf(d, k, lo, hi) return math.clamp(1 - d * k, lo, hi) end

-- 武器表（Config.Weapons[id]）按这一套改一份：开枪、换弹、准星、后坐、开镜都用它
function GM.apply(id, base, b)
  local D = GM.DEF[id]
  if not D or type(base) ~= "table" then return base end
  b = GM.clean(id, b)
  local w = table.clone(base)
  local s = GM.score(id, b)
  local d = {}
  for _, k in ipairs(GM.STATS) do d[k] = s[k] - (D.base[k] or 50) end
  -- 后坐（Fx.lua G.kick）：垂直管上抬和往后踢，水平管左右飘和横滚
  local rc = base.rc or RC0
  w.rc = { up = rc.up * kOf(d.vrec, K_REC, 0.35, 1.8), punch = rc.punch * kOf(d.vrec * 0.7, K_REC, 0.4, 1.6),
    side = rc.side * kOf(d.hrec, K_REC, 0.35, 1.8), roll = rc.roll * kOf(d.hrec * 0.7, K_REC, 0.4, 1.6) }
  -- 连射越打越散：后坐压得住的散得慢
  if base.bloom then
    local avg = (d.vrec + d.hrec) / 2
    w.bloom = { base.bloom[1] * kOf(avg, 0.008, 0.5, 1.6), base.bloom[2] * kOf(avg, 0.006, 0.6, 1.5), base.bloom[3], base.bloom[4] }
  end
  w.spread = (base.spread or 0) * kOf(d.hip, K_HIP, 0.4, 1.8)        -- 腰射
  w.adsK = (base.adsK or 1) * kOf(d.stab, 0.005, 0.6, 1.4)           -- 开镜精度
  w.swayK = kOf(d.stab, K_STAB, 0.4, 1.8)                             -- 开镜时枪 / 镜子里的晃动
  w.adsSpd = math.clamp(1 + d.hand * K_HAND, 0.5, 1.6)               -- 开镜、拔枪快慢（倍数）
  w.range = (base.range or 500) * math.clamp(1 + d.range * K_RANGE, 0.7, 1.5)
  w.mobK = math.clamp(1 + d.mob * K_MOB, 0.85, 1.1)                   -- 走路速度
  -- 各位的特殊效果
  local quiet = base.quiet
  for _, slot in ipairs(GM.SLOTS) do
    local it = b[slot] and GM.ITEM[b[slot]]
    if it then
      if it.quiet then quiet = true end
      if it.mag then w.mag = it.mag end
      if it.reload then w.reload = (base.reload or 2) * it.reload end
      if it.laser then w.laser = true end
      if it.light then w.light = true end
      if slot == "optic" then
        w.adsZoom = it.zoom
        if it.scope then
          w.scope, w.optic = it.zoom, it.scope
        else   -- 机械瞄具、红点、全息：开镜看着枪（不进目镜的像）
          w.scope, w.optic = nil, nil
        end
        w.dot = it.dot
      end
    end
  end
  w.quiet = quiet or nil
  w.build = b
  return w
end

-- 伤害随距离衰减（fall = { 从射程的几成开始掉, 到射程尽头剩几成 }；没写的不衰减）
function GM.dmgAt(w, dist)
  local dmg = w.dmg or 0
  local f = w.fall
  if not f or not dist then return dmg end
  local R = w.range or 500
  local a = R * f[1]
  if dist <= a then return dmg end
  local t = math.clamp((dist - a) / math.max(1, R - a), 0, 1)
  return dmg * (1 - t * (1 - f[2]))
end

-- 「有效射程」（米，界面上写的）：伤害开始衰减的距离；不衰减的写射程
function GM.effRange(w)
  local R = w.range or 500
  return math.floor(R * (w.fall and w.fall[1] or 1) / 2.8 + 0.5)
end

---------------------------------------------------------------- 配件装在枪上的哪儿

-- 第一人称 / 改枪界面的 M4（FPSView 的枪身骨骼坐标：+Z 朝枪口、+Y 朝上，格；照动作包的真 M4 量的）
--   bore 枪管轴线，tip A2 消焰器前端，rail 上机匣导轨顶面，under 护木下面，magTop 弹匣顶面中心（弹匣骨骼坐标）；
--   side 护木左侧导轨（枪身骨骼的 +X 是枪的左边：左手托在这边；第一人称镜头看得见的那一面，改枪界面也是看左侧）
GM.M4 = { bore = { 0.0095, 0.0505 }, tip = 1.439, rail = 0.142, under = -0.033, side = 0.094, sideY = 0.0545, magTop = { 0, 0.253, -0.041 } }
-- 每样配件在 M4 上的位置：z 枪口件的后端 / 瞄具的原点 / 握把、战术件的中心
GM.M4AT = {
  muz_comp = 1.249, muz_brake = 1.269, sup_socom = 1.37, sup_wrap = 1.37, sup_sr8 = 1.37,
  acog = 0.24, opt_acog6 = 0.2, opt_rds = 0.3, opt_holo = 0.28, opt_romeo = 0.24,
  grip_rvg = 0.74, grip_afg = 0.62, tac_light = 0.74, tac_peq = 0.74,
}

-- 配件 → { cf 装在哪（M4 枪身骨骼坐标；弹匣是弹匣骨骼坐标）, track 跟哪条骨骼, mz 装了以后的枪口（枪口件才有） }；
--   meta 是 OpticsMeta[配件的模型键]（量尺寸用）；不用装模型的返回 nil
function GM.m4Mount(item, meta)
  local it = GM.ITEM[item]
  if not it or not it.model then return nil end
  local M4 = GM.M4
  local bx, by = M4.bore[1], M4.bore[2]
  local slot = it.slot
  if slot == "muzzle" then
    local z = GM.M4AT[item] or 1.37
    local L = (meta and meta.size and meta.size[3]) or 0.3
    return { cf = CFrame.new(bx, by, z), track = "gun", mz = Vector3.new(bx, by, z + L) }
  elseif slot == "optic" then
    if item == "acog" then return { cf = CFrame.new(0, M4.rail, GM.M4AT.acog), track = "gun" } end   -- 原来那具：位置照旧
    local ex = 0   -- 光轴对正枪管（有的瞄具侧面有旋钮，包围盒中心不在光轴上）
    if it.eye then ex = it.eye[1] elseif meta and meta.eye then ex = meta.eye.c[1] elseif meta and meta.obj then ex = meta.obj.c[1] end
    return { cf = CFrame.new(bx - ex, M4.rail + (it.riser or 0), GM.M4AT[item] or 0.25), track = "gun", riser = it.riser }
  elseif slot == "grip" then
    return { cf = CFrame.new(bx, M4.under, GM.M4AT[item] or 0.7), track = "gun" }
  elseif slot == "mag" then
    local t = M4.magTop
    return { cf = CFrame.new(t[1], t[2], t[3]), track = "mag" }   -- 弹匣：两条弹匣骨骼（mag1 枪上的、mag2 换弹时手里的）都装
  elseif slot == "tac" then
    -- 左侧导轨：模型的底面（+Y 朝上）转成朝外（+X）贴在导轨上
    return { cf = CFrame.new(M4.side, M4.sideY, GM.M4AT[item] or 0.7) * CFrame.Angles(0, 0, -math.pi / 2), track = "gun" }
  end
  return nil
end

-- 镜片 / 窗玻璃该多透明（不是玻璃的返回 nil）：key 是模型键（和配件同名）
function GM.glassT(key, part)
  local it = GM.ITEM[key]
  return it and it.glass and it.glass[part] or nil
end

-- 瞄具的光轴（器材坐标）：{ eye 目镜 / 后窗中心, obj 物镜 / 前窗中心, r 目镜半径 }；机械瞄具、没有的返回 nil
function GM.sightOf(item, meta)
  local it = GM.ITEM[item]
  if not it then return nil end
  if it.eye and it.obj then
    return { eye = Vector3.new(it.eye[1], it.eye[2], it.eye[3]), obj = Vector3.new(it.obj[1], it.obj[2], it.obj[3]), r = it.eye[4] or 0.03 }
  end
  if not meta then return nil end
  local e, o = meta.eye, meta.obj
  if e and o then
    return { eye = Vector3.new(e.c[1], e.c[2], e.c[3]), obj = Vector3.new(o.c[1], o.c[2], o.c[3]), r = e.r or 0.03 }
  end
  if o then   -- 只量到一块窗玻璃（Romeo3）：光轴水平穿过它
    local c = Vector3.new(o.c[1], o.c[2], o.c[3])
    return { eye = c - Vector3.new(0, 0, 0.05), obj = c, r = o.r or 0.03 }
  end
  return nil
end

-- 第三人称：工具上零件拼的 M4（Weapons.lua makeTool 的 SHAPE.m4：−Z 朝前、把手在握把，比真枪大一倍左右；工具的 −X 是枪的左边）；
--   配件模型按各位的倍数放大（ACOG 原来就是 1.2 倍），+Z 朝前的器材坐标转 180° 装上
GM.TP = {
  m4 = { muzzle = { 0, 0.38, -3.55, 2.6 }, optic = { 0, 0.65, -0.5, 1.2 }, grip = { 0, 0.05, -1.75, 2.0 }, mag = { 0, 0.22, -0.8, 1.8 }, tac = { -0.225, 0.35, -1.7, 1.8 } },
}

return GM
