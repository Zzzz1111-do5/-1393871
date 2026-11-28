-- 多语言（模拟器）：python3 tools/mock/run.py tools/mock/i18n.lua
--   用户 11-28「多语言做一下」：简中、繁中、英、日、韩、俄、德、法、西、葡十种
--   ① 系统语言是日语（Roblox 的 LocaleId ja-jp）：客户端按日语起来，键（G.T）、代码里的中英对照（G.L）都查日语包，没翻的型号退回英文，参数照填
--   ② 机库界面上是日文（有假名），没有漏翻成中文的字（只有简体才有的字：这、们、车、设……）
--   ③ 八个译文包都在、条数够；Roblox 的 LocaleId → 语言（zh-tw、pt-br、es-mx……）；繁中由简体转（选择 → 選擇）
--   ④ 地图专用的说法（point.A@city）也有译文
--   ⑤ 设置里的语言下拉框：跟随系统 + 十种，选德语马上换成德语；选回「跟随系统」回到日语
--   ⑥ 主菜单、阵营页的语言键按 LIST 的顺序轮换
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check

R.locale = "ja-jp"
T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8421, true)
T.runUntil(function() return G.round ~= nil end, 30)
local C = T.C
R.run(2)
local RS = R.services.ReplicatedStorage
local Lang = R.require(RS:FindFirstChild("Lang"))
local function named(name)   -- 任何类型（T.findNamed 只找按钮）
  for _, d in ipairs(R.localPlayer.PlayerGui:GetDescendants()) do
    if d.Name == name and T.visible(d) then return d end
  end
end

print("① 系统语言是日语：客户端按日语起来")
check(C.lang == "ja", "G.lang = " .. tostring(C.lang))
check(not C.isZh(), "不算中文（排版按西文 / 日文走）")
local s1 = C.T("ui.deploy")
check(s1 == "配置", "键 ui.deploy → " .. s1)
local s2 = C.L("开镜灵敏度", "Aim sensitivity")
check(s2 == "照準時の感度", "对照「开镜灵敏度 / Aim sensitivity」→ " .. s2)
local s3 = C.T("aw.aim120")
check(s3 == "AIM-120", "没翻的型号退回英文：" .. s3)
local s4 = C.T("pve.level", 3)
check(s4 == "ミッション 3", "参数照填：" .. s4)
local s5 = C.L("不在表里的中文", "Not in any pack")
check(s5 == "Not in any pack", "译文包里没有的对照退回英文：" .. s5)

print("② 机库界面：日文，没有漏翻的中文")
local KANA = "\227[\129-\131]"   -- 平假名、片假名（UTF-8 E3 81～83 开头）
local SIMP = { "这", "们", "车", "设", "选", "击", "战", "机", "开", "进", "说", "对", "时", "会", "个", "为", "过", "动", "发", "后", "里", "从", "让", "门", "级", "装", "备" }
local kana, bad = 0, {}
for _, s in ipairs(T.texts()) do
  if s:find(KANA) then kana = kana + 1 end
  for _, ch in ipairs(SIMP) do
    if s:find(ch, 1, true) then bad[#bad + 1] = s break end
  end
end
check(kana >= 5, "看得见的字里有假名的 " .. kana .. " 处")
check(#bad == 0, "看得见的字里只有简体才有的字的 " .. #bad .. " 处" .. (#bad > 0 and ("：" .. table.concat(bad, " | "):sub(1, 400)) or ""))

print("③ 译文包、系统语言、繁中")
for _, l in ipairs(Lang.LIST) do
  if l.code ~= "zh" and l.code ~= "en" then
    local P = Lang.pack(l.code)
    local nk, np = 0, 0
    for _ in pairs(P and P.k or {}) do nk = nk + 1 end
    for _ in pairs(P and P.p or {}) do np = np + 1 end
    check(P ~= nil and nk >= 1500 and np >= 400, string.format("%s（%s）：键 %d 条、对照 %d 条", l.code, l.name, nk, np))
  end
end
check(#Lang.LIST == 10, "语言列表 " .. #Lang.LIST .. " 种")
local PICK = { ["zh-cn"] = "zh", ["zh-tw"] = "zh-TW", ["zh-hk"] = "zh-TW", ["en-us"] = "en", ["ja-jp"] = "ja", ["ko-kr"] = "ko",
  ["ru-ru"] = "ru", ["de-de"] = "de", ["fr-ca"] = "fr", ["es-mx"] = "es", ["pt-br"] = "pt", ["it-it"] = "en", ["th-th"] = "en" }
local pickOk = true
for id, want in pairs(PICK) do
  if Lang.pick(id) ~= want then pickOk = false print("    " .. id .. " → " .. tostring(Lang.pick(id)) .. "（该是 " .. want .. "）") end
end
check(pickOk, "Roblox 的 LocaleId → 语言（zh-tw → 繁中、pt-br → 葡、不支持的 → 英）")
local tw = Lang.t("zh-TW", "ui.chooseRole")
check(tw == "選擇兵種", "繁中：ui.chooseRole → " .. tw)
local tw2 = Lang.pair("zh-TW", "开镜灵敏度", "Aim sensitivity")
check(tw2 ~= "开镜灵敏度" and tw2:find("開", 1, true) ~= nil, "繁中对照：开镜灵敏度 → " .. tw2)
local ru = Lang.t("ru", "pve.level", 7)
check(ru == "МИССИЯ 7", "俄语带参数：" .. ru)
local ko = Lang.t("ko", "ui.youWon")
check(ko == "승리", "韩语：ui.youWon → " .. ko)

print("④ 地图专用的说法")
local oldMap = Lang.mapId
Lang.mapId = "city"
local pa = Lang.t("ja", "point.A")
local pf = Lang.t("fr", "point.A")
Lang.mapId = oldMap
check(pa == "A 製鉄所", "钢城的 A（日）：" .. pa)
check(pf == "A Aciérie", "钢城的 A（法）：" .. pf)

print("⑤ 设置里的语言下拉框")
R.as("client", function() C.openSettings("main") end)
R.run(0.3)
local drop = T.findNamed("Drop_lang")
check(drop ~= nil, "设置第一页有语言下拉框（" .. (drop and drop.Text or "没找到") .. "）")
local nOpt = 0
local opts = {}
if drop then
  T.press(drop)
  R.run(0.1)
  local list = named("DropList")
  if list then
    for _, o in ipairs(list:GetChildren()) do
      if o.ClassName == "TextButton" and o.Name:find("^Opt_") then nOpt = nOpt + 1 opts[tonumber(o.Name:sub(5))] = o end
    end
  end
end
check(nOpt == 11, "下拉框 " .. nOpt .. " 项（跟随系统 + 十种）")
local de = opts[8]
check(de ~= nil and de.Text:find("Deutsch", 1, true) ~= nil, "第 8 项是德语（" .. (de and de.Text or "?") .. "）")
if de then T.press(de) R.run(0.2) end
check(C.lang == "de", "选了德语：G.lang = " .. tostring(C.lang))
check(C.T("ui.deploy") == "Einsatz", "德语：ui.deploy → " .. C.T("ui.deploy"))
check(C.L("开镜灵敏度", "Aim sensitivity") == "Ziel-Empfindlichkeit", "德语对照：" .. C.L("开镜灵敏度", "Aim sensitivity"))
-- 选回「跟随系统」
if drop then
  T.press(drop)
  R.run(0.1)
  local list = named("DropList")
  local sys = list and list:FindFirstChild("Opt_1")
  if sys then T.press(sys) R.run(0.2) end
end
check(C.lang == "ja", "选回「跟随系统」：G.lang = " .. tostring(C.lang))
R.as("client", function() if C.closeSettings then C.closeSettings() end end)

print("⑥ 语言键轮换")
check(Lang.nextOf("zh") == "zh-TW" and Lang.nextOf("en") == "ja" and Lang.nextOf("pt") == "zh", "zh → zh-TW、en → ja、pt → 回到 zh")
check(Lang.nameOf("ko") == "한국어" and Lang.nameOf("ru") == "Русский", "语言名用它自己的写法")

R.run(1)
T.summary()
