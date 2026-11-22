-- Roblox全面大战场——坦克改装（用户 11-19：给坦克实现爆反和主动拦截系统，可以改坦克，像给飞机选导弹那样选装）
--   每型坦克三个改装位：爆反（标配——原模型上本来就有，99A 炮塔正面补贴了一片；不能拆）、主动防御（不装 / 硬杀伤拦截系统）、
--   车顶武器（原装机枪 / 艾布拉姆斯可换 GAU-8 加特林炮塔附件）。
--   出车时客户端的改装界面（Garage.lua）把选的发给服务器（Depots padSpawn → Armor），服务器装好、模型属性 Mods 写上（"aps=hk;roof=gau8"），
--   大家的客户端按它画发射器、雷达板、加特林；车速、武器表按改装改一份型号数据（applyDef：服务器的 e.def、自己开的 st.d 都用它）
--   爆反块的位置在 EraMeta.lua（tools/models/eralayout.py 量的），这里按模型键查
local RS = game:GetService("ReplicatedStorage")
local TM = {}

-- 选项：slot 哪个位，n / reload / gap 主动防御的弹数、每多少秒补一发、两次拦截最少隔几秒，spd 车速倍数（加装的重量），weapon 加的武器
TM.OPT = {
  era = { slot = "era", fixed = true },
  none = { slot = "aps" },
  hk = { slot = "aps", n = 4, reload = 30, gap = 0.65, spd = 0.97 },   -- 硬杀伤：两侧各一个发射器（各两发）、四角雷达板
  stock = { slot = "roof" },
  gau8 = { slot = "roof", weapon = "gau8", spd = 0.95 },   -- 车顶的 GAU-8 加特林炮塔附件（Daniel Skomorovsky 设计的虚构加装件）
}
TM.SLOTS = { "era", "aps", "roof" }
-- 用户 11-22：「坦克不要弄哪个机枪」——坦克不带机枪（VehDefs.TANK_MG）：车顶武器这一位（原装机枪 / GAU-8 加特林）也去掉
do
  local okV, VD = pcall(function() return require(RS:WaitForChild("VehDefs", 3)) end)
  if okV and type(VD) == "table" and VD.TANK_MG == false then TM.SLOTS = { "era", "aps" } end
end
-- 爆反分区（用户 11-22：「坦克我能选择在哪个地方贴爆反」）：tf 炮塔正面、ts 炮塔侧面、gl 首上、sk 侧裙板（EraMeta 每块的第 17 项）；
--   改装界面里每个区一个开关：装 / 不装；原模型上本来就有的区（EraMeta 的 own）拆不掉；少装一个区车轻一点（车速多 1.2%）
--   选的区写成 "tf+gl+sk"（改装串里 era=tf+gl+sk；一个都不装是 none）
TM.ZONES = { "tf", "ts", "gl", "sk" }
TM.ZSPD = 0.012
-- 没选过时贴哪些区：艾布拉姆斯出厂只有侧裙板的 ARAT（模型自带），炮塔、首上的补贴块要自己在改装界面里加；别的（99A、96）照原来全贴
TM.ERADEF = { m1a1 = "sk", m1a2 = "sk" }
-- 每型能选的（第一个是默认）
TM.FOR = {
  ztz99a = { era = { "era" }, aps = { "none", "hk" }, roof = { "stock" } },
  ztz96 = { era = { "era" }, aps = { "none", "hk" }, roof = { "stock" } },
  m1a2 = { era = { "era" }, aps = { "none", "hk" }, roof = { "stock", "gau8" } },
  m1a1 = { era = { "era" }, aps = { "none", "hk" }, roof = { "stock", "gau8" } },
}
-- 爆反型号：k 挨破甲类（火箭弹、导弹）时剩几成伤害，ke 挨穿甲弹时剩几成（重型爆反对穿甲弹也有用）
TM.ERA = {
  fy4 = { k = 0.22, ke = 0.75, name = "fy4" },
  fy2 = { k = 0.3, ke = 1, name = "fy2" },
  arat = { k = 0.35, ke = 1, name = "arat" },
}

function TM.has(id) return TM.FOR[id] ~= nil end

-- 这型坦克有哪些爆反区（有块的）、哪些是原模型自带的（拆不掉）；按 TM.ZONES 的顺序
function TM.eraZones(id)
  local L = TM.eraOf and TM.eraOf(id)
  if not L or not L.b then return {}, {} end
  local have, own = {}, {}
  for _, b in ipairs(L.b) do if b[17] then have[b[17]] = true end end
  for _, z in ipairs(L.own or {}) do own[z] = true end
  local list = {}
  for _, z in ipairs(TM.ZONES) do if have[z] then table.insert(list, z) end end
  return list, own
end
-- 装了哪些区（集合）：s 是 "tf+gl" / "none" / nil（nil、"era" 是默认：全装，同原来）
function TM.eraSet(s, id)
  local on = {}
  if (type(s) ~= "string" or s == "era") and id and TM.ERADEF[id] then s = TM.ERADEF[id] end
  if type(s) ~= "string" or s == "era" then
    for _, z in ipairs((TM.eraZones(id))) do on[z] = true end
    if not id then for _, z in ipairs(TM.ZONES) do on[z] = true end end
  elseif s ~= "none" then
    for z in string.gmatch(s, "%a+") do on[z] = true end
  end
  return on
end
local function cleanEra(id, want)
  local list, own = TM.eraZones(id)
  local on = TM.eraSet(want, id)
  for z in pairs(own) do on[z] = true end
  local out = {}
  for _, z in ipairs(list) do if on[z] then table.insert(out, z) end end
  return (#out > 0) and table.concat(out, "+") or "none"
end
TM.cleanEra = cleanEra

-- 选的改装（表）整理成合法的：没选的、不合法的用默认
function TM.clean(id, m)
  local F = TM.FOR[id]
  if not F then return nil end
  local out = {}
  for _, slot in ipairs(TM.SLOTS) do
    local want = type(m) == "table" and m[slot] or nil
    if slot == "era" then
      out.era = cleanEra(id, want)
    else
      local list = F[slot] or {}
      out[slot] = (want and table.find(list, want)) and want or list[1]
    end
  end
  return out
end

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
  for k, v in string.gmatch(s, "(%w+)=([%w%+]+)") do m[k] = v end
  return m
end

-- 型号数据按改装改一份（不改原表）：车速、加速、武器表；没有改装的型号原样返回
function TM.applyDef(d, m)
  if not d or not TM.FOR[d.id] then return d end
  if type(m) == "string" then m = TM.decode(m) end
  m = TM.clean(d.id, m)
  local k, weapons = 1, table.clone(d.weapons)
  for _, slot in ipairs(TM.SLOTS) do
    local o = TM.OPT[m[slot]]
    if o then
      k *= o.spd or 1
      if o.weapon then table.insert(weapons, o.weapon) end
    end
  end
  do   -- 爆反：比全装少几个区就轻几分
    local list = TM.eraZones(d.id)
    local on = TM.eraSet(m.era, d.id)
    local n = 0
    for _, z in ipairs(list) do if on[z] then n += 1 end end
    k *= 1 + TM.ZSPD * (#list - n)
  end
  local c = table.clone(d)
  c.speed, c.accel = d.speed * k, (d.accel or 10) * k
  c.weapons = weapons
  c.mods = m
  c.base = d   -- 原型号（别处要原值的时候用）
  return c
end

---------------------------------------------------------------- 爆反块（EraMeta）

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
-- 型号的爆反布局：{ kind, tur, b = { … }, aps, own }；没有的 nil
function TM.eraOf(id)
  local em, im = meta()
  if not em or not im or not im.alias then return nil end
  local key = im.alias[id]
  return key and em[key] or nil, key
end

-- 一块的四个量：中心、法线、宽方向（Vector3），宽、高、厚
function TM.block(b)
  local c = Vector3.new(b[2], b[3], b[4])
  local n = Vector3.new(b[5], b[6], b[7])
  local u = Vector3.new(b[8], b[9], b[10])
  return c, n, u, b[11], b[12], b[13]
end

-- 一块在车的坐标里（炮塔上的按炮塔转角 yaw 度转过去）：返回 CFrame（X 宽、Y 高、Z 朝外——LookVector 朝里），宽、高、厚
--   base：车底的 CFrame；炮塔转轴 tur（EraMeta 的，和 ImportedMeta 的 tur 一样）
function TM.blockCF(L, b, base, yaw)
  local c, n, u, w, h, t = TM.block(b)
  local v = n:Cross(u).Unit
  local local_ = CFrame.fromMatrix(c + n * (t / 2), u, v, n)
  if b[1] == "t" then
    local tur = Vector3.new(L.tur[1], L.tur[2], L.tur[3])
    local_ = CFrame.new(tur) * CFrame.Angles(0, -math.rad(yaw or 0), 0) * CFrame.new(-tur) * local_
  end
  return base * local_, w, h, t
end

-- 车顶加特林（GAU-8 附件）：转轴在炮塔顶左侧（装填手那边）、比顶面高 0.95 格，炮口在转轴前 KIT_MUZ 格；跟着炮俯仰
TM.KIT_MUZ = 6.2
function TM.kitPivot(L)
  local tur = Vector3.new(L.tur[1], L.tur[2], L.tur[3])
  local l = L.aps and L.aps.l and L.aps.l[1]
  local roof = l and (l[2] + 0.55) or (L.tb[5] - 1)
  return Vector3.new(tur.X - 1.9, roof + 0.95, tur.Z + 0.6)
end
-- 加特林的炮口（世界 CFrame，LookVector 朝外）：base 车底，yaw 炮塔转角、pitch 炮的俯仰（度）
function TM.kitMuzzle(L, base, yaw, pitch)
  local tur = Vector3.new(L.tur[1], L.tur[2], L.tur[3])
  local kp = TM.kitPivot(L)
  return base * CFrame.new(tur) * CFrame.Angles(0, -math.rad(yaw or 0), 0) * CFrame.new(kp - tur) * CFrame.Angles(math.rad(pitch or 0), 0, 0)
    * CFrame.new(0, 0, -TM.KIT_MUZ)
end

-- 这一区的块是不是原模型自带的（平时不另画）
function TM.own(L, b)
  if not L or not L.own then return false end
  return table.find(L.own, b[17]) ~= nil
end

return TM
