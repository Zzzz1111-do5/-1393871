-- Roblox全面大战场——坦克改装（用户 11-19：给坦克实现爆反和主动拦截系统，像给飞机选导弹那样选装；
--   用户 11-22 晚：「坦克要能自己选位置贴爆反」「要能有一整套的坦克改装体系」「用现实中的标准」「坦克上面就别贴了」「别挡住一些部位」）
--   出车时客户端的改装界面（Garage.lua）把选的发给服务器（Depots padSpawn → Armor），服务器校验（TM.clean）、装好，
--   模型属性 Mods 写上改装串（"era=fy4;ep=…;aps=gl5;…"），大家的客户端按它画爆反块、发射器、栅栏、扫雷犁、伪装网；
--   车速、加速、炮塔转速按加装的重量改一份型号数据（applyDef：服务器的 e.def、自己开的 st.d 都用它）
--   改装位（TM.SLOTS）：
--     era 爆反型号、ep 爆反贴在哪几格（逐格自选，EraMeta 的候选格；原车自带的格拆不掉）、aps 硬杀伤主动防护、ew 光电对抗（软杀伤）、
--     slat 栅栏装甲、belly 车底防雷板、eng 扫雷犁、cam 多光谱伪装网
--   数据尽量用公开资料的真实数字，出处写在旁边；查不到的标「估」（游戏里得有个数）
local RS = game:GetService("ReplicatedStorage")
local TM = {}

---------------------------------------------------------------- 各车的真实基本数据

-- t 战斗全重（吨）、hp 发动机功率（马力）、vmax 公路最大速度（公里 / 时）、ammo 主炮弹药基数（ready 自动装弹机 / 炮塔尾舱备便弹）
--   99A：维基百科 Type 99 tank（55 吨、1500 马力、公路 76 km/h、42 发其中自动装弹机 22 发）
--   96B：战斗全重 43 吨（HandWiki / Surf Wiki）、8V150 柴油机 1000 马力（维基百科；另有资料称 1200 马力）、公路约 70 km/h（各家 65–74）、42 发（自动装弹机 22）
--   M1A2 SEPv2：约 63 吨（SEPv3 加装后 66.8 吨）、AGT1500 燃气轮机 1500 马力、公路限速 67 km/h、42 发（炮塔尾舱 36 + 车体 6）
--   M1A1：约 57 吨（基型；HA 约 61 吨）、AGT1500、67 km/h、40 发（尾舱 34 + 车体 6）
TM.SPEC = {
  ztz99a = { t = 55, hp = 1500, vmax = 76, ammo = 42, ready = 22 },
  ztz96 = { t = 43, hp = 1000, vmax = 70, ammo = 42, ready = 22 },
  m1a2 = { t = 63, hp = 1500, vmax = 67, ammo = 42, ready = 36 },
  m1a1 = { t = 57, hp = 1500, vmax = 67, ammo = 40, ready = 34 },
  t90m = { t = 46.5, hp = 1130, vmax = 60, ammo = 43, ready = 22 },
  leo2a6 = { t = 62.3, hp = 1500, vmax = 68, ammo = 42, ready = 15 },   -- 豹 2A6：62.3 吨、MB 873 1500 马力、68 km/h、42 发（炮塔尾舱 15 发，有泄压板）
  leclerc = { t = 56.5, hp = 1500, vmax = 72, ammo = 40, ready = 22 },   -- 勒克莱尔：56.5 吨、V8X 1500 马力、72 km/h、40 发（尾舱自动装弹机 22 发）
  t72b3 = { t = 46, hp = 1130, vmax = 60, ammo = 45, ready = 22 },   -- T-72B3（2016 年型）：46 吨、V-92S2F 1130 马力、60 km/h、45 发（自动装弹机 22 发）
  t80u = { t = 46, hp = 1250, vmax = 70, ammo = 45, ready = 28 },   -- T-80U：46 吨、GTD-1250 燃气轮机、70 km/h、45 发（自动装弹机 28 发）   -- T-90M：46.5 吨、V-92S2F 1130 马力、60 km/h、43 发（自动装弹机 22 发）
  -- 11-27 拆开重叠的版本：能装改装（爆反、主动防护）的同族变型（改装页照同族那一型，见文件末尾），车重、功率按各自的
  m1a2sep3 = { t = 66.8, hp = 1500, vmax = 67, ammo = 42, ready = 36 },   -- M1A2 SEPv3：66.8 吨（73.6 短吨）、AGT1500、67 km/h、42 发
}

---------------------------------------------------------------- 爆反型号

-- k 挨单装药破甲弹（火箭弹）时剩几成伤害、kt 挨串联装药（反坦克导弹：前级先把爆反引爆）时剩几成、ke 挨尾翼稳定脱壳穿甲弹时剩几成，
--   kg 每格（一个盒子）加多重、th 盒子厚度倍数（重型爆反钢板厚、盒子更厚）
--   FY-2：第二代、轻型（对破甲弹）；FY-4：重型（对穿甲弹也有用，相当于接触-5：官方说能削掉约两成穿深）；
--   ARAT-1（M19 块）：每块 65 磅（美国陆军 2020 年报道）≈ 29.5 千克，对单装药火箭弹；ARAT-2（M32 块）叠在 M19 外面成双层，专门对付串联装药
TM.ERA = {
  fy2 = { k = 0.30, kt = 0.85, ke = 1.00, kg = 22, th = 1.0 },   -- 重量估
  fy4 = { k = 0.22, kt = 0.60, ke = 0.78, kg = 45, th = 1.35 },   -- 重量估（接触-5 一整套 2.8–3 吨）
  arat = { k = 0.35, kt = 0.85, ke = 1.00, kg = 29.5, th = 1.0 },
  arat2 = { k = 0.25, kt = 0.50, ke = 1.00, kg = 52, th = 1.6 },   -- M19 + M32；M32 的重量公开资料没有，估
}

---------------------------------------------------------------- 主动防护（硬杀伤）

-- 每套：launchers 发射单元（az 管哪个方位：炮塔坐标里的角度，0 朝前、正数往右；span 左右各管多少度；n 弹数），
--   elev 往上能管到多少度（再陡的攻顶弹拦不了）、look 雷达多远开始跟踪（格）、rng 在离车多远打（格）、gap 同一个发射单元两发至少隔多久（秒）、
--   regen 打掉的弹多久补一发（游戏里的补给，真车要乘员下车装填）、kg 重量、trav 炮塔转速倍数（加的重量让炮塔失衡）
--   GL5（北方工业）：4 个发射单元、4 部毫米波雷达，方位 360°、高低 20°（攻顶弹拦不了），离车 10 米（±1.5 米）拦截，探测距离 100 米以上（Army Recognition、army-guide）
--   Trophy（拉斐尔，M1A2 SEPv2 装）：两侧各一个能转的发射器，EL/M-2133 雷达四块平板天线 360° 覆盖，发射器再装填至少 1.5 秒；
--     加重约 5000 磅（Defense Daily），美国作战试验鉴定局：炮塔失衡、转动性能下降；每个发射器带几发没公开（估 4 发）
TM.APS = {
  gl5 = { kg = 600, elev = 20, look = 280, rng = 28, gap = 0.3, regen = 45,   -- 重量估
    launchers = { { az = -45, span = 45, n = 1 }, { az = 45, span = 45, n = 1 }, { az = -135, span = 45, n = 1 }, { az = 135, span = 45, n = 1 } } },
  trophy = { kg = 2268, elev = 45, look = 180, rng = 30, gap = 1.5, regen = 40, trav = 0.9,   -- elev 估
    launchers = { { az = -90, span = 95, n = 4 }, { az = 90, span = 95, n = 4 } } },
}

---------------------------------------------------------------- 光电对抗（软杀伤）

-- 激光告警：激光制导的导弹 / 炸弹（AirDefs 的 guide = "laser"：AKD-10、AGM-114、GBU-12、雷石……）冲着这辆车来时报警、报方向，
--   auto 自动打一组烟幕弹（烟幕挡住激光照射，导弹丢了目标）；dazzle 激光压制：照射源被干扰的概率（JD-3，公开资料很少，估）
--   kg 估
TM.EW = {
  lws = { kg = 60, auto = true, dazzle = 0 },
  jd3 = { kg = 120, auto = true, dazzle = 0.45 },
}

---------------------------------------------------------------- 其它加装件

-- 栅栏装甲：车尾、炮塔尾舱后面、侧面后段（离车身约半米）；对火箭弹（单装药）约五成有效（维基百科 Slat armor：大约挡下 50% 的火箭弹），
--   对导弹、炮弹没用；重量估 650 千克
-- 车底防雷板：防坦克雷、炸药炸在车底时伤害减半（估）；重量估 1300 千克
-- 扫雷犁（全宽扫雷犁，Pearson FWMP）：3600 千克，扫出 4.2 米宽的通路、深 175–300 毫米，犁地时车速 1–15 公里 / 时，升起 11 秒；
--   放下时把前面的雷翻到两边（不炸车）；扫雷犁在车头，挡不住驾驶员潜望镜（低于车头）
-- 多光谱伪装网（萨博梭鱼 MCS 那一类）：挡可见光、近红外、热红外、雷达；游戏里敌人（机器人、热像仪）发现你的距离按 0.7 算；重量估 300 千克
TM.KIT = {
  slat = { kg = 650, p = 0.5 },
  belly = { kg = 1300, k = 0.5 },
  plow = { kg = 3600, lane = 11.8, vcap = 15, raise = 11 },
  mcs = { kg = 300, spot = 0.7 },
}

---------------------------------------------------------------- 改装位、选项

-- 选项：slot 哪个位（none 各位都用）
TM.OPT = {
  none = { slot = "*" },
  fy2 = { slot = "era" }, fy4 = { slot = "era" }, arat = { slot = "era" }, arat2 = { slot = "era" },
  gl5 = { slot = "aps" }, trophy = { slot = "aps" },
  lws = { slot = "ew" }, jd3 = { slot = "ew" },
  slat = { slot = "slat" }, belly = { slot = "belly" }, plow = { slot = "eng" }, mcs = { slot = "cam" },
  -- 以前的（车顶武器：坦克不带机枪以后这一位去掉了；hk 旧的硬杀伤 = 这型车的那一套）
  stock = { slot = "roof" },
  gau8 = { slot = "roof", weapon = "gau8", spd = 0.95 },
}
TM.SLOTS = { "era", "ep", "aps", "ew", "slat", "belly", "eng", "cam" }
-- 改装界面里分几页：装甲（爆反型号、贴在哪、栅栏、防雷板）、主动防护（硬杀伤、软杀伤）、工程（扫雷犁）、伪装
TM.CATS = {
  { id = "armor", slots = { "era", "ep", "slat", "belly" } },
  { id = "active", slots = { "aps", "ew" } },
  { id = "eng", slots = { "eng" } },
  { id = "cam", slots = { "cam" } },
}
-- 用户 11-22：「坦克不要弄哪个机枪」——坦克不带机枪（VehDefs.TANK_MG）：车顶武器这一位（原装机枪 / GAU-8 加特林）也去掉
local TANK_MG = false
local VD = nil   -- 型号表（noEra、like 按它查：TM.eraOf、文件末尾的退同族）
do
  local okV, vd = pcall(function() return require(RS:WaitForChild("VehDefs", 3)) end)
  if okV and type(vd) == "table" then
    VD = vd
    if vd.TANK_MG ~= false then TANK_MG = true end
  end
end
if TANK_MG then table.insert(TM.SLOTS, "roof") end

-- 每型能选的（第一个是默认）；爆反型号：原车装的放第一个
TM.FOR = {
  ztz99a = { era = { "fy4", "fy2" }, aps = { "none", "gl5" }, ew = { "none", "jd3" }, slat = { "none", "slat" }, belly = { "none", "belly" },
    eng = { "none", "plow" }, cam = { "none", "mcs" }, roof = { "stock" } },
  ztz96 = { era = { "fy2", "fy4" }, aps = { "none", "gl5" }, ew = { "none", "lws" }, slat = { "none", "slat" }, belly = { "none", "belly" },
    eng = { "none", "plow" }, cam = { "none", "mcs" }, roof = { "stock" } },
  t90m = { era = { "fy4", "fy2" }, aps = { "none", "gl5" }, ew = { "none", "lws" }, slat = { "none", "slat" }, belly = { "none", "belly" },
    eng = { "none", "plow" }, cam = { "none", "mcs" }, roof = { "stock" } },
  m1a2 = { era = { "arat", "arat2" }, aps = { "none", "trophy" }, ew = { "none", "lws" }, slat = { "none", "slat" }, belly = { "none", "belly" },
    eng = { "none", "plow" }, cam = { "none", "mcs" }, roof = { "stock", "gau8" } },
  m1a1 = { era = { "arat", "arat2" }, aps = { "none", "trophy" }, ew = { "none", "lws" }, slat = { "none", "slat" }, belly = { "none", "belly" },
    eng = { "none", "plow" }, cam = { "none", "mcs" }, roof = { "stock", "gau8" } },
}

-- 爆反的区（EraMeta 每格的第 17 项）：tf 炮塔正面、ts 炮塔侧面、gl 首上、sk 侧裙板前段；自选位置多给的：tb 炮塔侧面后半、sr 侧裙板后段、lf 下首
TM.ZONES = { "tf", "ts", "tb", "gl", "lf", "sk", "sr" }
-- 没选过时贴哪些区：艾布拉姆斯出厂只有侧裙板的 ARAT（模型自带），别的（99A、96）照原来四个区全贴
TM.ERADEF = { m1a1 = { "sk" }, m1a2 = { "sk" } }
local ZDEF = { "tf", "ts", "gl", "sk" }

-- 预设（改装界面「预设」页）：照真车的几种常见搭配
--   z 贴哪几个区（nil 不动爆反位置）、set 其它位改成什么
TM.PRESETS = {
  ztz99a = {
    { id = "factory", z = { "tf", "ts", "gl", "sk" }, set = { era = "fy4", aps = "none", ew = "none", slat = "none", belly = "none", eng = "none", cam = "none" } },
    { id = "front", z = { "tf", "ts", "gl", "lf", "sk" }, set = { era = "fy4", aps = "gl5", ew = "jd3" } },
    { id = "urban", z = { "tf", "ts", "tb", "gl", "sk", "sr" }, set = { era = "fy4", aps = "gl5", ew = "jd3", slat = "slat", belly = "belly" } },
    { id = "breach", z = { "tf", "ts", "gl", "sk" }, set = { era = "fy4", eng = "plow", belly = "belly" } },
  },
  ztz96 = {
    { id = "factory", z = { "tf", "ts", "gl", "sk" }, set = { era = "fy2", aps = "none", ew = "none", slat = "none", belly = "none", eng = "none", cam = "none" } },
    { id = "front", z = { "tf", "ts", "gl", "lf", "sk" }, set = { era = "fy4", aps = "gl5" } },
    { id = "urban", z = { "tf", "ts", "tb", "gl", "sk", "sr" }, set = { era = "fy4", aps = "gl5", ew = "lws", slat = "slat", belly = "belly" } },
    { id = "breach", z = { "tf", "ts", "gl", "sk" }, set = { eng = "plow", belly = "belly" } },
  },
  t90m = {   -- 出厂就是「化石」重型爆反四个区全贴；城市型加车尾、侧面后段的栅栏和防地雷底板（叙利亚、乌克兰战场的样子）
    { id = "factory", z = { "tf", "ts", "gl", "sk" }, set = { era = "fy4", aps = "none", ew = "none", slat = "none", belly = "none", eng = "none", cam = "none" } },
    { id = "front", z = { "tf", "ts", "gl", "lf", "sk" }, set = { era = "fy4", ew = "lws" } },
    { id = "urban", z = { "tf", "ts", "tb", "gl", "sk", "sr" }, set = { era = "fy4", ew = "lws", slat = "slat", belly = "belly" } },
    { id = "breach", z = { "tf", "ts", "gl", "sk" }, set = { era = "fy4", eng = "plow", belly = "belly" } },
  },
  m1a2 = {
    { id = "factory", z = { "sk" }, set = { era = "arat", aps = "none", ew = "none", slat = "none", belly = "none", eng = "none", cam = "none" } },
    { id = "tusk1", z = { "sk", "sr" }, set = { era = "arat", slat = "slat" } },   -- TUSK I：两侧 ARAT-1、车尾栅栏
    { id = "tusk2", z = { "sk", "sr" }, set = { era = "arat2", slat = "slat", belly = "belly" } },   -- TUSK II：ARAT-1 外面再叠 ARAT-2
    { id = "trophy", z = { "sk", "sr" }, set = { era = "arat", aps = "trophy" } },   -- M1A2 SEPv2 + Trophy（美国陆军驻欧部队）
    { id = "breach", z = { "sk" }, set = { eng = "plow", belly = "belly" } },
  },
  m1a1 = {
    { id = "factory", z = { "sk" }, set = { era = "arat", aps = "none", ew = "none", slat = "none", belly = "none", eng = "none", cam = "none" } },
    { id = "tusk1", z = { "sk", "sr" }, set = { era = "arat", slat = "slat" } },
    { id = "tusk2", z = { "sk", "sr" }, set = { era = "arat2", slat = "slat", belly = "belly" } },
    { id = "trophy", z = { "sk", "sr" }, set = { era = "arat", aps = "trophy" } },   -- 美国海军陆战队的 M1A1 也装了 Trophy
    { id = "breach", z = { "sk" }, set = { eng = "plow", belly = "belly" } },
  },
}

function TM.has(id) return TM.FOR[id] ~= nil end

---------------------------------------------------------------- 爆反格（EraMeta）

local EM, IM = nil, nil
local function meta()
  if EM == nil then
    local ok, r = pcall(function() return require(RS:WaitForChild("EraMeta", 3)) end)
    EM = ok and type(r) == "table" and r or false
    local ok2, r2 = pcall(function() return require(RS:WaitForChild("ImportedMeta", 3)) end)
    IM = ok2 and type(r2) == "table" and r2 or false
  end
  return EM, IM
end
-- 型号的爆反布局：{ kind, tur, tb, hb, roof, b = { … }, aps, own }；没有的 nil
--   11-27：借同族模型、真车没有这些块的型号（VehDefs 的 noEra：T-80B、T-72 乌拉尔 / A / B、M1～M1A2 SEP、96 式）返回 nil——
--   原来按模型拿 EraMeta，T-80B 平白多 22 格接触-5、T-72 乌拉尔 / A / B 37 格；服务器 Era、驾驶界面、VehModels、改装页都走这里，一处挡住
function TM.eraOf(id)
  local d = VD and VD.get and VD.get(id)
  if d and d.noEra then return nil end
  local em, im = meta()
  if not em or not im or not im.alias then return nil end
  local key = im.alias[id]
  return key and em[key] or nil, key
end

-- 这一格是不是原模型自带的（拆不掉、平时不另画）
function TM.own(L, b)
  if not L or not L.own then return false end
  return table.find(L.own, b[17]) ~= nil
end

-- 这型坦克有哪些区（按 TM.ZONES 的顺序）、哪些区是原车自带的
function TM.eraZones(id)
  local L = TM.eraOf(id)
  if not L or not L.b then return {}, {} end
  local have, own = {}, {}
  for _, b in ipairs(L.b) do if b[17] then have[b[17]] = true end end
  for _, z in ipairs(L.own or {}) do own[z] = true end
  local list = {}
  for _, z in ipairs(TM.ZONES) do if have[z] then table.insert(list, z) end end
  return list, own
end

-- 爆反位置串：每格一位（原车自带的那几格不算，总是装着），6 位一个字符（base64url）
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local B64I = {}
for i = 1, #B64 do B64I[string.sub(B64, i, i)] = i - 1 end
function TM.epEncode(on, n)
  local out = {}
  for c = 0, math.ceil(n / 6) - 1 do
    local v = 0
    for bit = 0, 5 do
      local i = c * 6 + bit + 1
      if i <= n and on[i] then v += 2 ^ bit end
    end
    table.insert(out, string.sub(B64, v + 1, v + 1))
  end
  -- 末尾全是 A（没贴）的去掉，串短一点
  local s = table.concat(out)
  s = string.gsub(s, "A+$", "")
  return (s == "") and "-" or s   -- 一格都没贴写 "-"（和「没选过」区分开）
end
function TM.epDecode(s, n)
  local on = {}
  if type(s) ~= "string" or s == "-" then return on end
  for c = 1, math.min(#s, math.ceil(n / 6)) do
    local v = B64I[string.sub(s, c, c)]
    if not v then return {} end
    for bit = 0, 5 do
      local i = (c - 1) * 6 + bit + 1
      if i <= n and math.floor(v / 2 ^ bit) % 2 == 1 then on[i] = true end
    end
  end
  return on
end

-- 按区选格：zones 是区名的表（集合或列表）
function TM.cellsInZones(id, zones)
  local L = TM.eraOf(id)
  local on = {}
  if not L or not L.b then return on end
  local zs = {}
  for k, v in pairs(zones or {}) do
    if type(k) == "number" then zs[v] = true elseif v then zs[k] = true end
  end
  for i, b in ipairs(L.b) do if b[17] and zs[b[17]] then on[i] = true end end
  return on
end
-- 没选过时贴哪些格
function TM.defaultCells(id) return TM.cellsInZones(id, TM.ERADEF[id] or ZDEF) end

-- 选的改装里贴了哪些格（含原车自带的）：返回 { [格号] = true }
function TM.cellsOn(id, m)
  local L = TM.eraOf(id)
  if not L or not L.b then return {} end
  if type(m) == "string" then m = TM.decode(m) end
  local on
  local ep = type(m) == "table" and m.ep or nil
  if type(ep) == "string" then on = TM.epDecode(ep, #L.b) else on = TM.defaultCells(id) end
  for i, b in ipairs(L.b) do if TM.own(L, b) then on[i] = true end end
  return on
end

-- 左右对称的那一格（EraMeta 每格第 18 项；没有 nil）
function TM.mirror(L, i)
  local b = L and L.b and L.b[i]
  local j = b and b[18]
  if j and j > 0 and j ~= i then return j end
  return nil
end

-- 兼容老的按区开关（老存档 / 老界面的 era="tf+gl"）：返回装了的区的集合
function TM.eraSet(s, id)
  local on = {}
  if type(s) == "table" then
    for i in pairs(TM.cellsOn(id, s)) do
      local L = TM.eraOf(id)
      local b = L and L.b[i]
      if b and b[17] then on[b[17]] = true end
    end
    return on
  end
  if (type(s) ~= "string" or s == "era" or TM.ERA[s]) then
    local list = id and (TM.ERADEF[id] or ZDEF) or TM.ZONES
    for _, z in ipairs(list) do on[z] = true end
  elseif s ~= "none" then
    for z in string.gmatch(s, "%a+") do on[z] = true end
  end
  return on
end

---------------------------------------------------------------- 改装串

function TM.encode(m)
  if not m then return "" end
  local parts = {}
  for _, slot in ipairs(TM.SLOTS) do
    if m[slot] then table.insert(parts, slot .. "=" .. m[slot]) end
  end
  return table.concat(parts, ";")
end

function TM.decode(s)
  local m = {}
  if type(s) ~= "string" then return m end
  for k, v in string.gmatch(s, "(%w+)=([%w%+%-_]+)") do m[k] = v end
  return m
end

-- 选的改装（表）整理成合法的：没选的、不合法的用默认；老的写法（era="tf+gl"、aps="hk"）换成新的
function TM.clean(id, m)
  local F = TM.FOR[id]
  if not F then return nil end
  if type(m) == "string" then m = TM.decode(m) end
  m = type(m) == "table" and m or {}
  local out = {}
  local L = TM.eraOf(id)
  local n = (L and L.b) and #L.b or 0
  -- 爆反：era 是型号；以前 era 写的是区（"tf+gl" / "none" / "era"）——换成格
  local era, ep = m.era, m.ep
  if type(era) == "string" and not TM.ERA[era] then
    if type(ep) ~= "string" and era ~= "era" then
      local zs = {}
      if era ~= "none" then for z in string.gmatch(era, "%a+") do zs[z] = true end end
      ep = TM.epEncode(TM.cellsInZones(id, zs), n)
    end
    era = nil
  end
  out.era = (era and table.find(F.era, era)) and era or F.era[1]
  if n > 0 then
    local on
    if type(ep) == "string" and (ep == "-" or not string.find(ep, "[^%w%-_]")) then on = TM.epDecode(ep, n) else on = TM.defaultCells(id) end
    for i, b in ipairs(L.b) do if TM.own(L, b) then on[i] = nil end end   -- 自带的不记（总是装着）
    out.ep = TM.epEncode(on, n)
  end
  local aps = m.aps
  if aps == "hk" then aps = F.aps[2] end
  for _, slot in ipairs(TM.SLOTS) do
    if slot ~= "era" and slot ~= "ep" then
      local list = F[slot] or { "none" }
      local want = (slot == "aps") and aps or m[slot]
      out[slot] = (want and table.find(list, want)) and want or list[1]
    end
  end
  return out
end
TM.cleanEra = function(id, want) return TM.clean(id, { era = want }).ep end   -- 兼容

---------------------------------------------------------------- 重量、机动

-- 加装件一共多重（千克），分项：{ era, aps, ew, slat, belly, eng, cam }
function TM.mass(id, m)
  m = TM.clean(id, m)
  local out = { era = 0, aps = 0, ew = 0, slat = 0, belly = 0, eng = 0, cam = 0 }
  if not m then return 0, out, 0 end
  local L = TM.eraOf(id)
  local E = TM.ERA[m.era]
  local native = TM.ERA[TM.FOR[id].era[1]]
  local cells = 0
  if L and L.b and E then
    for i in pairs(TM.cellsOn(id, m)) do
      local b = L.b[i]
      if b then
        cells += 1
        -- 自带的格换了型号：多出（或少了）两种盒子的差
        out.era += TM.own(L, b) and (E.kg - native.kg) or E.kg
      end
    end
  end
  local A = TM.APS[m.aps]
  if A then out.aps = A.kg end
  local W = TM.EW[m.ew]
  if W then out.ew = W.kg end
  if m.slat == "slat" then out.slat = TM.KIT.slat.kg end
  if m.belly == "belly" then out.belly = TM.KIT.belly.kg end
  if m.eng == "plow" then out.eng = TM.KIT.plow.kg end
  if m.cam == "mcs" then out.cam = TM.KIT.mcs.kg end
  local sum = 0
  for _, v in pairs(out) do sum += v end
  return sum, out, cells
end

-- 这套改装下的性能：t 战斗全重、pw 单位功率（马力 / 吨）、vmax 公路最大速度、vK 车速倍数、aK 加速倍数、travK 炮塔转速倍数
--   车重了：加速按单位功率（功率 / 重量）掉；越野极速按功率受限的那部分掉（指数 0.6 是公路限速和越野两头折中），公路限速不变的部分不算
function TM.stats(id, m)
  local S = TM.SPEC[id]
  if not S then return nil end
  m = TM.clean(id, m)
  local add, parts, cells = TM.mass(id, m)
  local t = S.t + add / 1000
  local vK = math.clamp((S.t / t) ^ 0.6, 0.55, 1)
  local aK = math.clamp(S.t / t, 0.5, 1)
  local travK = 1
  local A = TM.APS[m.aps]
  if A and A.trav then travK *= A.trav end
  return { t = t, add = add, parts = parts, cells = cells, pw = S.hp / t, hp = S.hp, vmax = S.vmax * vK, vK = vK, aK = aK, travK = travK,
    ammo = S.ammo, ready = S.ready }
end

-- 型号数据按改装改一份（不改原表）：车速、加速、炮塔转速、武器表；没有改装的型号原样返回
--   同一个改装串的结果缓存起来（自己开的车每帧都要）
local cache = {}
function TM.applyDef(d, m)
  if not d or not TM.FOR[d.id] then return d end
  local ck = nil
  if type(m) == "string" or m == nil then
    ck = d.id .. "|" .. (m or "")
    local hit = cache[ck]
    if hit and hit.base == d then return hit end
  end
  m = TM.clean(d.id, m)
  local st = TM.stats(d.id, m)
  local k, weapons = 1, table.clone(d.weapons)
  for _, slot in ipairs(TM.SLOTS) do
    local o = TM.OPT[m[slot]]
    if o and o.slot == slot then
      k *= o.spd or 1
      if o.weapon then table.insert(weapons, o.weapon) end
    end
  end
  local c = table.clone(d)
  c.speed, c.accel = d.speed * k * st.vK, (d.accel or 10) * k * st.aK
  if d.turret and st.travK ~= 1 then
    c.turret = table.clone(d.turret)
    c.turret.trav = (d.turret.trav or 40) * st.travK
  end
  c.weapons = weapons
  c.mods = m
  c.kit = { era = m.era, aps = m.aps ~= "none" and m.aps or nil, ew = m.ew ~= "none" and m.ew or nil, slat = m.slat == "slat",
    belly = m.belly == "belly", plow = m.eng == "plow", mcs = m.cam == "mcs" }
  c.stats = st
  c.base = d   -- 原型号（别处要原值的时候用）
  if ck then cache[ck] = c end
  return c
end

---------------------------------------------------------------- 几何

-- 一格的四个量：中心、法线、宽方向（Vector3），宽、高、厚
function TM.block(b)
  local c = Vector3.new(b[2], b[3], b[4])
  local n = Vector3.new(b[5], b[6], b[7])
  local u = Vector3.new(b[8], b[9], b[10])
  return c, n, u, b[11], b[12], b[13]
end

-- 一格在车的坐标里（炮塔上的按炮塔转角 yaw 度转过去）：返回 CFrame（X 宽、Y 高、Z 朝外——LookVector 朝里），宽、高、厚
--   base：车底的 CFrame；炮塔转轴 tur（EraMeta 的，和 ImportedMeta 的 tur 一样）；th 厚度倍数（重型爆反的盒子厚）
function TM.blockCF(L, b, base, yaw, th)
  local c, n, u, w, h, t = TM.block(b)
  t *= th or 1
  local v = n:Cross(u).Unit
  local local_ = CFrame.fromMatrix(c + n * (t / 2), u, v, n)
  if b[1] == "t" then
    local tur = Vector3.new(L.tur[1], L.tur[2], L.tur[3])
    local_ = CFrame.new(tur) * CFrame.Angles(0, -math.rad(yaw or 0), 0) * CFrame.new(-tur) * local_
  end
  return base * local_, w, h, t
end

-- 车顶加特林（GAU-8 附件，坦克不带机枪以后不用了）：转轴在炮塔顶左侧（装填手那边）、比顶面高 0.95 格，炮口在转轴前 KIT_MUZ 格；跟着炮俯仰
TM.KIT_MUZ = 6.2
function TM.kitPivot(L)
  local tur = Vector3.new(L.tur[1], L.tur[2], L.tur[3])
  local l = L.aps and L.aps.l and L.aps.l[1]
  local roof = l and (l[2] + 0.55) or (L.tb[5] - 1)
  return Vector3.new(tur.X - 1.9, roof + 0.95, tur.Z + 0.6)
end
function TM.kitMuzzle(L, base, yaw, pitch)
  local tur = Vector3.new(L.tur[1], L.tur[2], L.tur[3])
  local kp = TM.kitPivot(L)
  return base * CFrame.new(tur) * CFrame.Angles(0, -math.rad(yaw or 0), 0) * CFrame.new(kp - tur) * CFrame.Angles(math.rad(pitch or 0), 0, 0)
    * CFrame.new(0, 0, -TM.KIT_MUZ)
end

-- 一发弹从哪个方位打来（炮塔坐标：0 朝前、正数往右，−180~180 度）、仰角（度，从上往下砸是正的）
--   base 车底 CFrame、yaw 炮塔转角、from 来袭弹的位置
function TM.bearing(base, yaw, from)
  local tcf = base * CFrame.Angles(0, -math.rad(yaw or 0), 0)
  local lp = tcf:PointToObjectSpace(from)
  local az = math.deg(math.atan2(lp.X, -lp.Z))
  local horiz = math.sqrt(lp.X * lp.X + lp.Z * lp.Z)
  local el = math.deg(math.atan2(lp.Y, math.max(horiz, 1e-3)))
  return az, el
end

---------------------------------------------------------------- 同族的变型退到同族（11-27 拆重叠的版本）
-- VehDefs 里写了 like 的变型（M1A2 SEPv3 借 M1A2 SEPv2、T-90A 借 T-90M、99 式借 99A……）没单独登记改装时，能选的、默认贴哪些区、预设
--   照同族那一型（爆反格按同一个模型的 EraMeta，本来就一样）；车重、功率按各自的 SPEC（没写才退到同族：TM.stats 要有它）。
--   noEra 的不退：真车没有这些块，也就没有改装页（要给就单独写一份不带爆反的 TM.FOR）
if VD and type(VD.D) == "table" then
  for id, d in pairs(VD.D) do
    local like = d.like
    if like and not d.noEra and TM.FOR[id] == nil and TM.FOR[like] ~= nil then
      TM.FOR[id] = TM.FOR[like]
      TM.ERADEF[id] = TM.ERADEF[id] or TM.ERADEF[like]
      TM.PRESETS[id] = TM.PRESETS[id] or TM.PRESETS[like]
      TM.SPEC[id] = TM.SPEC[id] or TM.SPEC[like]
    end
  end
end

return TM
