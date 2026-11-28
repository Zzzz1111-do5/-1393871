-- 弹种名按语言写（模拟器）：python3 tools/mock/run.py tools/mock/ammonames.lua
--   用户 11-28「目前局内我分辨不出来弹种 这些还是根据语言改变吧 比如我选了中文 穿甲弹就要写上」：
--   ① 每一种弹都分得出弹种（Ballistics.kindOf：尾翼稳定脱壳穿甲弹 / 脱壳 / 硬芯 / 穿爆 / 风帽 / 破甲 / 多用途 / 高爆 / 霰弹 / 导弹 / 射流）；
--      型号去掉名字后面的类型（「BR-365 APHE」→「BR-365」、只剩口径的写成「125 mm」）
--   ② 简中、英文都有全称、短名；繁中、日韩俄德法西葡的译文包里每个弹种都有（按键给的，「AP」「HE」不串成一个字的小牌子）
--   ③ 坐上 M1A2：弹药栏每一格主炮弹左下都写着中文短名（原来只有选中那格写、还是英文缩写），名牌「M829A3 · 尾翼稳定脱壳穿甲弹」；
--      换成英文：短名、全称是北约缩写
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check

T.mapName = "city"   -- 默认图（沙海在模拟器里建得太慢）
local G = T.boot()   -- 同 wttank.lua：先当步兵出生再上车
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
local RS = R.services.ReplicatedStorage
local BAL = R.require(RS:FindFirstChild("Ballistics"))
local Lang = R.require(RS:FindFirstChild("Lang"))

print("① 每一种弹都分得出弹种")
local KINDS = { "apfsds", "apds", "apcr", "aphe", "apbc", "ap", "heatfs", "heat", "heatmp", "mpat", "hefrag", "hesh", "can", "atgm", "jet" }
local none = {}
local n = 0
for k in pairs(BAL.AMMO) do
  n = n + 1
  if not BAL.kindOf(k) then none[#none + 1] = k end
end
check(#none == 0, string.format("%d 种弹都有弹种（没分出来的：%s）", n, table.concat(none, ", ")))
local WANT = { m829a3 = "apfsds", dtc10 = "apfsds", bm42 = "apfsds", dm53 = "apfsds", dm13 = "apds", m392 = "apds", br365p = "apcr", br365 = "aphe",
  br412 = "aphe", br412d = "apbc", m830 = "heatmp", dm12 = "heatmp", heat125 = "heatfs", bk31 = "heatfs", m456 = "heat", dm12h = "heat", m830a1 = "mpat",
  of26 = "hefrag", he125 = "hefrag", m1028 = "can", refleks = "atgm", jet120 = "jet" }
local wrong = {}
for k, want in pairs(WANT) do
  if BAL.kindOf(k) ~= want then wrong[#wrong + 1] = k .. "=" .. tostring(BAL.kindOf(k)) .. "（该是 " .. want .. "）" end
end
check(#wrong == 0, "弹种分对了（" .. (#wrong == 0 and "抽查 " .. #(function() local t = {} for k in pairs(WANT) do t[#t + 1] = k end return t end)() .. " 种" or table.concat(wrong, "；")) .. "）")
local DES = { br365 = "BR-365", heat125 = "125 mm", apfsds69 = "100 mm", m830 = "M830", xm578 = "XM578", dm13 = "DM13", m829a3 = "M829A3" }
local bad = {}
for k, want in pairs(DES) do
  if BAL.desig(k) ~= want then bad[#bad + 1] = k .. "→" .. BAL.desig(k) end
end
check(#bad == 0, "型号去掉了后面的类型（" .. (#bad == 0 and "BR-365 APHE → BR-365、125 HEAT → 125 mm" or table.concat(bad, "；")) .. "）")

print("② 各种语言都有")
local miss = {}
for _, kd in ipairs(KINDS) do
  for _, p in ipairs({ "ammo.t.", "ammo.s." }) do
    local zh, en = Lang.t("zh", p .. kd), Lang.t("en", p .. kd)
    if not zh or zh == p .. kd or not en or en == p .. kd then miss[#miss + 1] = p .. kd end
  end
end
check(#miss == 0, "简中、英文全称和短名都有" .. (#miss > 0 and ("（缺 " .. table.concat(miss, ", ") .. "）") or ""))
check(Lang.t("zh", "ammo.t.apfsds") == "尾翼稳定脱壳穿甲弹" and Lang.t("zh", "ammo.t.ap") == "穿甲弹" and Lang.t("zh", "ammo.s.heat") == "破甲",
  "中文：尾翼稳定脱壳穿甲弹 / 穿甲弹 / 破甲")
local packMiss = {}
for _, code in ipairs({ "zh-TW", "ja", "ko", "ru", "de", "fr", "es", "pt" }) do
  local ok, pk = pcall(function() return R.require(RS:FindFirstChild("LangPacks"):FindFirstChild(code)) end)
  for _, kd in ipairs(KINDS) do
    for _, p in ipairs({ "ammo.t.", "ammo.s." }) do
      if not (ok and pk and pk.k and type(pk.k[p .. kd]) == "string" and pk.k[p .. kd] ~= "") then packMiss[#packMiss + 1] = code .. ":" .. p .. kd end
    end
  end
end
check(#packMiss == 0, "繁中、日韩俄德法西葡每个弹种都有译文" .. (#packMiss > 0 and ("（缺 " .. table.concat(packMiss, ", "):sub(1, 300) .. "）") or ""))
do
  local ok, ja = pcall(function() return R.require(RS:FindFirstChild("LangPacks"):FindFirstChild("ja")) end)
  check(ok and ja.k["ammo.t.ap"] == "徹甲弾" and ja.k["ammo.t.hefrag"] == "榴弾", "日文全称是整个词（徹甲弾、榴弾；不是别处一个字的小牌子「徹」「榴」）")
end

print("③ 坐上 M1A2：弹药栏每格写弹种")
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8302, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "def"
me.Team = G.TEAM.def
me.Neutral = false
me:SetAttribute("Side", "def")
G.pushOne(P)
R.run(1)
local C = T.C
check(C.isZh(), "客户端是中文（模拟器的系统语言）")
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "base")
R.run(1.5)
local VD = R.require(RS:FindFirstChild("VehDefs"))
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or T.V3(G.Map.CAMP.x, 0, G.Map.CAMP.z)
local def = VD.get("m1a2")
local bx, bz = hp.X + 30, hp.Z
local e = G.newVehicle("def", "m1a2", G.vehBaseAt(def, bx, bz, T.V3(0, 0, -1)))
if hrp then me.Character:PivotTo(T.CF(bx + def.W / 2 + 4, G.Map.height(bx, bz) + 3, bz)) end
R.run(0.5)
T.act("enterVeh", e.id)
T.runUntil(function() return C.drive ~= nil end, 10)
check(P.vehicle == e and C.drive ~= nil, "坐上了 M1A2")
T.runUntil(function() return G.round.phase == "battle" end, 60)
R.run(2)
local gui = me.PlayerGui:FindFirstChild("WtTank")
check(gui ~= nil and gui.Enabled, "战雷坦克界面开着")
local tags, plate = {}, nil
for _, d in ipairs(me.PlayerGui:GetDescendants()) do
  if d.Name == "Tag" and d.ClassName == "TextLabel" and T.visible(d) and d.Text ~= "" then tags[#tags + 1] = d.Text end
  if d.Name == "AmmoName" then plate = d end
end
print("   格子左下：" .. table.concat(tags, " / "))
print("   名牌：" .. tostring(plate and plate.Text))
local nAm = #(BAL.GUN[def.weapons[1]] or {})
local zhTags = 0
for _, t in ipairs(tags) do if t:find("[\228-\233]") then zhTags = zhTags + 1 end end
check(#tags >= nAm and zhTags >= nAm, string.format("主炮 %d 种弹每格都写着中文弹种（%d 格有字、%d 格中文）", nAm, #tags, zhTags))
check(plate ~= nil and plate.Text:find("尾翼稳定脱壳穿甲弹", 1, true) ~= nil, "名牌：M829A3 · 尾翼稳定脱壳穿甲弹")
local seen, dup = {}, nil
for _, t in ipairs(tags) do if seen[t] then dup = t end seen[t] = true end
check(dup == nil, "每一格的短名都不一样（M830 多用途破甲弹、M830A1 多用途反坦克弹分得开）" .. (dup and ("：重复的「" .. dup .. "」") or ""))
C.lang = "en"
local nm, ty, tg = C.ammoInfo("m829a3")
check(nm == "M829A3" and ty == "APFSDS" and tg == "APFSDS", string.format("换成英文：%s · %s（短名 %s）", tostring(nm), tostring(ty), tostring(tg)))
C.lang = "zh"
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
