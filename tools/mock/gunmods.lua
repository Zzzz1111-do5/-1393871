-- 改枪数据（GunMods.lua）单测：python3 tools/mock/run.py tools/mock/gunmods.lua
--   改枪码来回转一遍还是原来那套（M4 全部组合、狙击枪）、校验位能挡住抄错的；clean 换掉装不了 / 没解锁的；
--   apply 的数按配件变（弹匣容量、换弹、后坐、散布、射程、消音）；等级表、解锁列表；伤害衰减
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check
T.scripts = dofile(MOCK_DIR .. "/load.lua")(R, SRC_DIR)
local RS = R.services.ReplicatedStorage
local GM = R.require(RS:FindFirstChild("GunMods"))
local Config = R.require(RS:FindFirstChild("Config"))
local W = Config.Weapons

-- 改枪码：M4 每一种组合都转回原样
local D = GM.DEF.m4
local n, bad, seen = 0, 0, {}
local function each(slots, i, b, f)
  if i > #slots then f(b) return end
  local slot = slots[i]
  for _, x in ipairs(D.slots[slot]) do
    b[slot] = x[1]
    each(slots, i + 1, b, f)
  end
end
each(GM.SLOTS, 1, {}, function(b)
  n = n + 1
  local code = GM.code("m4", b)
  if seen[code] then bad = bad + 1 end
  seen[code] = true
  local id, b2 = GM.parse(code)
  if id ~= "m4" then bad = bad + 1 return end
  for _, slot in ipairs(GM.SLOTS) do if b2[slot] ~= b[slot] then bad = bad + 1 return end end
  -- 小写、加空格、O/0 混着写也认
  local id3 = GM.parse("  " .. string.lower(code) .. " ")
  if id3 ~= "m4" then bad = bad + 1 end
end)
check(n == 6 * 6 * 3 * 5 * 3 and bad == 0, string.format("M4 的 %d 种组合改枪码都能转回原样（出错 %d）", n, bad))
local c0 = GM.code("m4", GM.default("m4"))
print("    默认 M4 的改枪码：" .. c0 .. "    推荐 CQB：" .. GM.code("m4", D.presets[1].b))
-- 抄错一位、相邻两位写反：校验挡住（每一个码的每一位换成每一个别的字符）
local B32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
local tried, wrong = 0, 0
for code in pairs(seen) do
  local dash = string.find(code, "-", 1, true)
  for i = dash + 1, #code do
    local ch = string.sub(code, i, i)
    for j = 1, #B32 do
      local alt = string.sub(B32, j, j)
      if alt ~= ch then
        tried = tried + 1
        if GM.parse(string.sub(code, 1, i - 1) .. alt .. string.sub(code, i + 1)) then wrong = wrong + 1 end
      end
    end
    if i < #code and string.sub(code, i + 1, i + 1) ~= ch then
      tried = tried + 1
      if GM.parse(string.sub(code, 1, i - 1) .. string.sub(code, i + 1, i + 1) .. ch .. string.sub(code, i + 2)) then wrong = wrong + 1 end
    end
  end
end
check(wrong == 0, string.format("改枪码抄错一位 / 相邻写反都认不出来（试了 %d 种，漏掉 %d）", tried, wrong))
check(select(3, GM.parse("AK47-1234")) == "gun" and select(3, GM.parse("随便写的")) == "bad", "不是改枪码 / 别的枪的码：说清楚原因")
local sid, sb = GM.parse(GM.code("sniper", { muzzle = "sup_sr8" }))
check(sid == "sniper" and sb.muzzle == "sup_sr8", "狙击枪的改枪码")

-- clean：装不了的、没解锁的换成默认
local b = GM.clean("m4", { muzzle = "sup_sr8", optic = "nope", grip = "grip_afg", mag = "mag_drum", tac = "tac_peq" }, 8)
check(b.muzzle == "fh_a2" and b.optic == "acog" and b.grip == "grip_afg" and b.mag == "mag_std" and b.tac == "tac_none",
  "8 级：SR8 / 弹鼓 / 激光还没解锁，换成默认；AFG（8 级）能装")
local b2 = GM.clean("m4", { muzzle = "sup_sr8", mag = "mag_drum" }, 1, true)
check(b2.muzzle == "sup_sr8" and b2.mag == "mag_drum", "全部解锁（Studio / unlockAll）时照选的")
check(GM.clean("sniper", { muzzle = "muz_comp" }).muzzle == "muz_none", "狙击枪装不了补偿器")

-- apply：数按配件变
local base = W.m4
local w0 = GM.apply("m4", base, GM.default("m4"))
check(w0.mag == 30 and math.abs(w0.reload - base.reload) < 1e-6 and w0.scope == 3.5 and w0.optic == "acog", "默认（ACOG、原装弹匣）：30 发、换弹照旧、3.5 倍")
local wd = GM.apply("m4", base, { mag = "mag_drum", muzzle = "sup_socom", optic = "opt_holo", grip = "grip_rvg", tac = "tac_peq" })
check(wd.mag == 60 and wd.reload > base.reload * 1.3, string.format("弹鼓 60 发、换弹 %.2f 秒（原来 %.2f）", wd.reload, base.reload))
check(wd.quiet == true and w0.quiet == nil, "消音器：开枪不上雷达（quiet）")
check(wd.scope == nil and wd.optic == nil and wd.dot == "holo" and wd.adsZoom == 1.5, "全息：不进目镜的像，开镜 1.5 倍、全息圈")
check(wd.laser == true and wd.spread < w0.spread, string.format("激光：腰射散布 %.3f°（默认 %.3f°）", wd.spread, w0.spread))
local wv = GM.apply("m4", base, { muzzle = "muz_comp", grip = "grip_rvg" })
check(wv.rc.up < w0.rc.up * 0.85, string.format("补偿器 + 垂直握把：每发上抬 %.3f°（默认 %.3f°）", wv.rc.up, w0.rc.up))
local wr = GM.apply("m4", base, { muzzle = "sup_sr8" })
check(wr.range > w0.range and GM.effRange(wr) > GM.effRange(w0), string.format("长消音器：有效射程 %d 米（默认 %d 米）", GM.effRange(wr), GM.effRange(w0)))
check(base.mag == 30 and base.rc.up == 0.3, "原来的武器表没被改动（apply 改的是复制的一份）")
local w6 = GM.apply("m4", base, { optic = "opt_acog6" })
check(w6.scope == 6 and w6.optic == "acog6" and w6.adsSpd < w0.adsSpd, "6 倍 ACOG：6 倍、开镜更慢")
local wi = GM.apply("m4", base, { optic = "iron" })
check(wi.scope == nil and wi.adsSpd > w0.adsSpd, "机械瞄具：开镜最快")

-- 伤害衰减：近处满伤，射程尽头剩七成多
check(GM.dmgAt(w0, 50) == w0.dmg and math.abs(GM.dmgAt(w0, w0.range) - w0.dmg * 0.72) < 0.01, "伤害衰减：近处满伤、射程尽头 72%")

-- 等级
local lv, a, nx = GM.level("m4", 0)
check(lv == 1 and a == 0 and nx == 200, "0 经验：1 级，下一级 200")
check(GM.level("m4", 950) == 4 and GM.level("m4", 999999) == 15 and GM.level("sniper", 999999) == 5, "经验 → 等级；满级封顶（M4 15 级、狙击枪 5 级）")
local un = GM.unlocksBetween("m4", 1, 3)
check(#un == 4, "升到 3 级解锁：补偿器、垂直握把、T1 红点、20 发弹匣（" .. table.concat(un, ",") .. "）")
-- 每样配件都有名字的字条（Lang）
local Lang = R.require(RS:FindFirstChild("Lang"))
local miss = {}
for id in pairs(GM.ITEM) do
  if not Lang.zh["gm.item." .. id] or not Lang.en["gm.item." .. id] then table.insert(miss, id) end
end
for _, k in ipairs(GM.STATS) do if not Lang.zh["gm.st." .. k] then table.insert(miss, "gm.st." .. k) end end
for _, slot in ipairs(GM.SLOTS) do if not Lang.zh["gm.slot." .. slot] then table.insert(miss, "gm.slot." .. slot) end end
check(#miss == 0, "配件、性能、改装位都有中英文名字" .. ((#miss > 0) and ("（缺 " .. table.concat(miss, ",") .. "）") or ""))
-- 配件的模型都在 OpticsMeta 里
local OM = R.require(RS:FindFirstChild("OpticsMeta"))
local noModel = {}
for id, it in pairs(GM.ITEM) do if it.model and not OM[it.model] then table.insert(noModel, id) end end
check(#noModel == 0, "配件的模型都转换好了（OpticsMeta）" .. ((#noModel > 0) and ("（缺 " .. table.concat(noModel, ",") .. "）") or ""))

print(T.fails == 0 and "全部通过" or ("有 " .. T.fails .. " 项不对"))
