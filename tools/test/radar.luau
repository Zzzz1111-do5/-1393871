--!nocheck
-- 机载雷达数据（src/ReplicatedStorage/Radars.lua，纯数据，一两秒跑完）：lune run tools/test/radar.luau
--   用户 11-27：「飞机雷达按型号照战雷做、能用键控制雷达方向」
--   ① 科技树每一项拿到自己的雷达（借型号的版本也是：F-16A 是 APG-66、苏-30SM 是 N011M……）；没有对空雷达的（歼-6、轰-6K、A-10、B-2、MQ-9、苏-25、
--      直升机）返回空；科技树空中树里新加的飞机没在这张表里就报出来（记得在 RD.OF / RD.VAR 配雷达）
--   ② 每部雷达字段齐全、数说得通（锁定距离 < 搜索距离、扫描宽度不超过万向架、近战模式都有扫描区……）；量程随真实距离单调；
--      APG-68、KLJ-5、SL-8A、N035 的游戏量程跟原来 AirDefs RADAR 表（×2.5）差不到 15%；AWG-9 的边扫边跟只能用 ±40°×2、±20°×4；APG-68 一帧 4 秒
--   ③ 资料卡（Radars.card）：中英文的字都在 Lang 里（没有漏翻的键），APG-66 写「只能单目标跟踪」、N011M 写边扫边跟 15 批、没有雷达写「没有对空雷达」；
--      Fly.lua / Radar.lua 用到的 rd.* 提示都有中英文
--   ④ 模式、扫描（第 4、5 步）：RD.modes——没有边扫边跟的（APG-66、N001、N019、早期 APG-63、SL-8A）按 Alt+E 跳过 TWS，有近战模式的都能进 ACM；
--      AWG-9 的 TWS 只能用 twsScans；每种近战模式的扫描区（RD.acmGeo）在万向架里；近战自动截获 13850 格（真机 10 海里）；记忆外推 2 秒；
--      亮点暗掉的时间比一帧长（RD.fade：机械扫描 ±60°×4 行一帧 8 秒，亮点 8.8 秒）
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local function load(path, env)
	return luau.load(fs.readFile(path), { debugName = path, environment = env or {} })()
end
local RD = load("src/ReplicatedStorage/Radars.lua")
local TT = load("src/ReplicatedStorage/TechTree.lua", { Color3 = roblox.Color3 })
local Lang = load("src/ReplicatedStorage/Lang.lua")

local bad = 0
local function check(ok, msg)
	print((ok and "  通过 " or "  不对 ") .. msg)
	if not ok then bad += 1 end
end

print("① 科技树每一项 → 雷达")
local WANT = {
	cn_j8ii = "sl8a", cn_j10a = "klj3", cn_j10c = "klj10", cn_j11 = "n001e", cn_j11b = "t1493", cn_j16 = "j16", cn_j15t = "j15t", cn_j20 = "klj5", cn_j35 = "j35",
	us_f16a = "apg66", us_f16c = "apg68", us_f14a = "awg9", us_f15a = "apg63", us_f15c = "apg63c", jp_f15j = "apg63c", us_f15e = "apg70", us_f22a = "apg77",
	us_f35a = "apg81", jp_f35a = "apg81", jp_f15jm = "apg63v1", jp_f2a = "japg1",
	ru_mig29 = "n019", ru_su27 = "n001", ru_su27sm = "n001ve", ru_su30sm = "n011m", ru_su35s = "n035", ru_t50 = "n036t", ru_su57 = "n036",
}
local NONE = { cn_j6 = true, cn_h6k = true, us_a10a = true, us_a10c = true, us_b2 = true, us_mq9 = true, ru_su25 = true }
local wrong, unknown, nAir = {}, {}, 0
for _, nat in ipairs(TT.NATIONS) do
	for _, br in ipairs({ "air", "heli" }) do
		for _, it in ipairs(TT.list[nat][br] or {}) do
			local r = RD.of(it.play, it.key)
			local got = r and r.key or "无"
			if br == "air" then nAir += 1 end
			local want = WANT[it.key] or ((NONE[it.key] or br == "heli") and "无") or nil
			if want == nil then
				table.insert(unknown, it.key .. "（" .. got .. "）")
			elseif want ~= got then
				table.insert(wrong, it.key .. " 要 " .. want .. " 拿到 " .. got)
			end
		end
	end
end
check(#wrong == 0, "科技树 " .. nAir .. " 架飞机各拿到自己的雷达" .. ((#wrong > 0) and ("：" .. table.concat(wrong, "，")) or ""))
check(#unknown == 0, "科技树空中树没有漏配的飞机" .. ((#unknown > 0) and ("（新加的：" .. table.concat(unknown, "、") .. "——在 Radars.lua 的 RD.OF / RD.VAR 配雷达，再写进这个测试）") or ""))
for k in pairs(WANT) do check(TT.byKey[k] ~= nil, "科技树里有 " .. k) end
local sample = { { "f16", "us_f16a", "APG-66" }, { "j16", "ru_su30sm", "N011M" }, { "f16", nil, "APG-68(V)5" }, { "su27", nil, "N001" }, { "f15", "jp_f15j", "APG-63" },
	{ "j11", "cn_j11", "N001E" }, { "j10", "cn_j10a", "KLJ-3" } }
for _, s in ipairs(sample) do
	local r = RD.of(s[1], s[2])
	check(r ~= nil and r.short == s[3], string.format("%s%s → %s（%s）", s[1], s[2] and (" + " .. s[2]) or "", s[3], tostring(r and r.short)))
end
check(RD.of("su27", nil) == RD.T.n001 and RD.of("su35", nil) == RD.T.n035, "苏-27 借苏-35S 的模型，雷达照旧是 N001（不退回 like）")
local noRadar = {}
for _, id in ipairs({ "j6", "h6k", "gj11", "gj2", "a10c", "mq9", "b2", "su25", "z20", "ah64e", "mi24", "ka52", "tiger", "uh60" }) do
	if RD.of(id) then table.insert(noRadar, id) end
end
check(#noRadar == 0, "没有对空雷达的型号返回空" .. ((#noRadar > 0) and ("（这些有了：" .. table.concat(noRadar, " ") .. "）") or ""))
check(RD.of(nil, nil) == nil and RD.of("j20", "us_a10a") == RD.T.klj5, "空型号返回空；科技树键不在 RD.VAR 里照型号取")
local nT = 0
for _ in pairs(RD.T) do nT += 1 end
check(nT == 27, "一共 27 部雷达（" .. nT .. "）")
local used = {}
for _, k in pairs(RD.OF) do used[k] = true end
for _, k in pairs(RD.VAR) do used[k] = true end
local orphan = {}
for k in pairs(RD.T) do if not used[k] then table.insert(orphan, k) end end
check(#orphan == 0, "每部雷达都有飞机用" .. ((#orphan > 0) and ("（没人用：" .. table.concat(orphan, " ") .. "）") or ""))

print("② 字段、数")
local KIND, ARR = { pd = true, pulse = true }, { mech = true, pesa = true, aesa = true }
local probs = {}
local function prob(k, why) table.insert(probs, k .. "：" .. why) end
for k, r in pairs(RD.T) do
	for _, f in ipairs({ "name", "en", "short", "rwr" }) do
		if type(r[f]) ~= "string" or r[f] == "" then prob(k, "缺 " .. f) end
	end
	if not KIND[r.kind] then prob(k, "kind " .. tostring(r.kind)) end
	if not ARR[r.arr] then prob(k, "arr " .. tostring(r.arr)) end
	for _, f in ipairs({ "km", "range", "lock", "az", "elU", "elD", "rate", "notch", "tws", "ldK" }) do
		if type(r[f]) ~= "number" or r[f] < 0 then prob(k, "缺 " .. f) end
	end
	if r.key ~= k then prob(k, "key 不对") end
	if not (r.lock < r.range) then prob(k, "锁定距离不比搜索距离近") end
	if r.el ~= math.max(r.elU, r.elD) then prob(k, "el 不是 max(elU, elD)") end
	if not (r.ldK > 0 and r.ldK <= 1) then prob(k, "ldK " .. tostring(r.ldK)) end
	if r.kind == "pd" and r.notch <= 0 then prob(k, "脉冲多普勒没有置零门限") end
	if type(r.scans) ~= "table" or #r.scans == 0 then
		prob(k, "没有扫描方式")
	else
		for i, s in ipairs(r.scans) do
			if not (s[1] > 0 and s[1] <= r.az and s[2] >= 1 and s[2] <= 10) then prob(k, "第 " .. i .. " 种扫描方式 ±" .. tostring(s[1]) .. "°×" .. tostring(s[2])) end
		end
	end
	if r.tws > 0 and not ((r.eng or 0) >= 1 and r.eng <= r.tws) then prob(k, "边扫边跟没写同时攻击几个") end
	for _, i in ipairs(r.twsScans or {}) do if not r.scans[i] then prob(k, "twsScans 指了没有的扫描方式 " .. i) end end
	for _, a in ipairs(r.acm or {}) do
		if not (RD.ACM[a] or (r.acmGeo and r.acmGeo[a])) then prob(k, "近战模式 " .. a .. " 没有扫描区") end
		if not RD.ACM_TAG[a] then prob(k, "近战模式 " .. a .. " 没有屏上缩写") end
	end
	if r.lpi and not (r.lpi > 0 and r.lpi < 1) then prob(k, "lpi " .. tostring(r.lpi)) end
end
table.sort(probs)
check(#probs == 0, "27 部雷达字段齐全、数说得通" .. ((#probs > 0) and ("：" .. table.concat(probs, "；")) or ""))
local list = {}
for _, r in pairs(RD.T) do table.insert(list, r) end
table.sort(list, function(a, b) return a.km < b.km end)
local mono = true
for i = 2, #list do if list[i].range < list[i - 1].range then mono = false end end
check(mono, "游戏量程随真实发现距离单调（" .. list[1].key .. " " .. list[1].range .. " 格 … " .. list[#list].key .. " " .. list[#list].range .. " 格）")
local OLD = { apg68 = 11000 * 2.5, klj5 = 16000 * 2.5, sl8a = 8000 * 2.5, n035 = 17500 * 2.5 }   -- 原来 AirDefs RADAR 表 × REAL.radar
for k, old in pairs(OLD) do
	local r = RD.T[k]
	local d = (r.range - old) / old
	check(math.abs(d) < 0.15, string.format("%s 量程 %d 格，原来 %d 格（差 %+.0f%%）", r.short, r.range, old, d * 100))
end
local aw = RD.T.awg9
local t1, t2 = aw.scans[aw.twsScans[1]], aw.scans[aw.twsScans[2]]
check(#aw.twsScans == 2 and t1[1] == 40 and t1[2] == 2 and t2[1] == 20 and t2[2] == 4, "AWG-9 的边扫边跟只能用 ±40°×2、±20°×4")
check(math.abs(RD.frame(RD.T.apg68, 1) - 4) < 1e-9, string.format("APG-68 默认扫描（±60°×2 行、60°/秒）一帧 4 秒（%.2f）", RD.frame(RD.T.apg68, 1)))
check(RD.frame(RD.T.apg77, 1) < 1.5 and RD.frame(RD.T.n019, 1) > 4, string.format("相控阵扫得快（APG-77 一帧 %.1f 秒）、机械扫描慢（N019 %.1f 秒）", RD.frame(RD.T.apg77, 1), RD.frame(RD.T.n019, 1)))
check(RD.half(RD.T.n035) == 60 and RD.T.n035.az == 120 and RD.half(RD.T.awg9) == 40, "默认扫描宽度：N035 ±60°（万向架 ±120°）、AWG-9 ±40°")
check(RD.T.sl8a.kind == "pulse" and RD.T.apg66.tws == 0 and RD.T.n001.tws == 0 and RD.T.n019.tws == 0 and RD.T.apg63.tws == 0, "SL-8A 是脉冲雷达；APG-66、N001、N019、早期 APG-63 没有边扫边跟")
check(RD.tag(RD.T.awg9, "bore") == "PLM" and RD.tag(RD.T.apg68, "bore") == "BORE" and RD.MODE_TAG.rws == "RWS", "屏上缩写：AWG-9 瞄准线写 PLM，别的写 BORE；搜索 RWS")

print("③ 资料卡、Lang")
local function Tz(k, ...) return Lang.t("zh", k, ...) end
local function Te(k, ...) return Lang.t("en", k, ...) end
local raw = {}
for k, r in pairs(RD.T) do
	for _, lang in ipairs({ "zh", "en" }) do
		local rows = RD.card(r, lang == "zh" and Tz or Te, lang == "en")
		for _, row in ipairs(rows) do
			local s = row[1]
			if type(s) ~= "string" or s:find("tech%.radar") or s:find("rd%.[a-z]") or s:find("{%d}") then table.insert(raw, k .. "/" .. lang .. "：" .. tostring(s)) end
		end
		if #rows < 7 then table.insert(raw, k .. "/" .. lang .. " 只有 " .. #rows .. " 行") end
	end
end
check(#raw == 0, "27 部雷达的资料卡中英文都翻好了" .. ((#raw > 0) and ("：" .. table.concat(raw, "；")) or ""))
local function cardText(r, lang)
	local out = {}
	for _, row in ipairs(RD.card(r, lang == "en" and Te or Tz, lang == "en")) do table.insert(out, row[1]) end
	return table.concat(out, " | ")
end
local c66, c11, c0 = cardText(RD.of("f16", "us_f16a")), cardText(RD.of("j16", "ru_su30sm")), cardText(nil)
print("    F-16A：" .. c66)
print("    苏-30SM：" .. c11)
print("    F-14A（英文）：" .. cardText(RD.T.awg9, "en"))
check(c66:find("AN/APG-66", 1, true) ~= nil and c66:find("只能单目标跟踪", 1, true) ~= nil and c66:find("机械扫描", 1, true) ~= nil, "F-16A：APG-66、机械扫描、只能单目标跟踪")
check(c11:find("N011M", 1, true) ~= nil and c11:find("边扫边跟 15 批", 1, true) ~= nil and c11:find("无源相控阵", 1, true) ~= nil, "苏-30SM：N011M 无源相控阵、边扫边跟 15 批")
check(c0:find("没有对空雷达", 1, true) ~= nil, "没有雷达的写「没有对空雷达」")
check(cardText(RD.T.klj5):find("（估）", 1, true) ~= nil and cardText(RD.T.apg68):find("（估）", 1, true) == nil, "外界估的（KLJ-5）写「估」，公开的（APG-68）不写")
local miss = {}
for _, k in ipairs({ "rd.keys", "rd.keys2", "rd.noTgt", "rd.isOff", "rd.cantSee", "rd.lockFar", "rd.unlock", "wt.radarOn", "wt.radarOff", "wt.radarRange",
	"air.radarLost", "air.radarLostNotch", "air.radarNotch", "air.radarClutter", "rd.zone", "rd.scanT", "rd.modeT", "rd.m.rws", "rd.m.tws", "rd.m.acm", "rd.center", "rd.alt" }) do
	if not (Lang.zh[k] and Lang.en[k]) then table.insert(miss, k) end
end
check(#miss == 0, "Fly.lua / Radar.lua 用到的提示都有中英文" .. ((#miss > 0) and ("（缺 " .. table.concat(miss, " ") .. "）") or ""))
check(Lang.zh["air.helpJet"]:find("Alt+F", 1, true) ~= nil and Lang.en["air.helpJetKb"]:find("Alt+F", 1, true) ~= nil, "开飞机的按键说明写了 Alt+F 雷达锁定")
local helpOk = true
for _, k in ipairs({ "air.helpJet", "air.helpJetKb" }) do
	for _, lang in ipairs({ "zh", "en" }) do
		for _, key in ipairs({ "Alt+E", "Alt+Z", "Alt+C" }) do
			if not Lang[lang][k]:find(key, 1, true) then helpOk = false end
		end
	end
end
check(helpOk, "开飞机的按键说明（中英）写了 Alt+E 模式、Alt+Z 扫描方式、Alt+C 天线回中")
local zh1, zh2 = Lang.t("zh", "rd.zone", "60", "2"), Lang.t("en", "rd.scanT", "30", "4", "4.0")
check(zh1 == "±60° · 2 行" and zh2 == "Scan ±30° · 4 bar (frame 4.0 s)", "雷达屏的扫描区字样：" .. zh1 .. " / " .. zh2)

print("④ 模式、扫描")
local function has(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
local noTws, acmAll, geoBad = {}, true, {}
for k, r in pairs(RD.T) do
	local ms = RD.modes(r)
	if ms[1] ~= "rws" then table.insert(geoBad, k .. " 第一个模式不是 RWS") end
	if has(ms, "tws") ~= (r.tws > 0) then table.insert(geoBad, k .. " 有没有 TWS 跟批数对不上") end
	if r.tws == 0 then table.insert(noTws, k) end
	if not has(ms, "acm") then acmAll = false end
	for _, a in ipairs(r.acm or {}) do
		local g = RD.acmGeo(r, a)
		if not (g and g.az > 0 and g.el1 > g.el0 and g.az <= r.az and g.el1 <= r.elU and g.el0 >= -r.elD) then table.insert(geoBad, k .. " 近战 " .. a .. " 的扫描区出了万向架") end
	end
	for i = 1, #r.scans do
		local sc = r.scans[i]
		if sc[2] * RD.BAR > r.elU + r.elD then table.insert(geoBad, k .. " 第 " .. i .. " 种扫描比俯仰万向架还高") end
		if RD.fade(r, i) < RD.frame(r, i) then table.insert(geoBad, k .. " 亮点没扫完一帧就暗了") end
	end
end
table.sort(noTws)
check(#geoBad == 0, "模式、近战扫描区、扫描高度都说得通" .. ((#geoBad > 0) and ("：" .. table.concat(geoBad, "；")) or ""))
check(table.concat(noTws, " ") == "apg63 apg66 n001 n001e n019 sl8a", "没有边扫边跟（Alt+E 跳过 TWS）：" .. table.concat(noTws, " "))
check(acmAll, "每部雷达都有近战模式（Alt+E 能进 ACM）")
check(RD.scanOk(RD.T.awg9, "tws", 1) and not RD.scanOk(RD.T.awg9, "tws", 2) and RD.scanOk(RD.T.awg9, "tws", 4) and RD.scanOk(RD.T.awg9, "rws", 2)
	and RD.scanOk(RD.T.apg68, "tws", 3), "AWG-9 的 TWS 只能用第 1、4 种扫描（RWS 都能用）；APG-68 的 TWS 都能用")
check(RD.ACQ == 13850, "近战自动截获 " .. RD.ACQ .. " 格（真机 10 海里）")
check(RD.MEM == 2 and RD.MODE_TAG.mem == "MEM" and RD.MODE_TAG.stt == "STT", "STT 丢了先记忆外推 2 秒（屏上 STT MEM）")
check(math.abs(RD.fade(RD.T.apg68, 2) - 8.8) < 1e-9 and math.abs(RD.fade(RD.T.klj5, 1) - 2.6) < 1e-9, string.format("亮点多久暗掉：APG-68 ±60°×4 行 %.1f 秒、KLJ-5 默认 %.1f 秒", RD.fade(RD.T.apg68, 2), RD.fade(RD.T.klj5, 1)))
check(RD.acmGeo(RD.T.awg9, "bore").az == 1.2 and RD.acmGeo(RD.T.apg68, "vert").el1 == 50 and RD.acmGeo(RD.T.apg66, "vert").el1 == 30, "近战扫描区：F-14 的 PLM 用自己的（±1.2°），APG-68 竖扫到 +50°、APG-66 到 +30°")

print(bad == 0 and "全部通过" or ("有 " .. bad .. " 项不对"))
process.exit(bad == 0 and 0 or 1)
