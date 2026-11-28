-- 设置界面 + 兑换码（用户 11-25「设置一个兑换码 在设置里」「那个设置界面不好看 重做」「兑换码Zhengyongshuo直接解锁所有载具」）：
--   python3 tools/mock/run.py tools/mock/settings.lua
--   ① 进服不出主菜单，直接机库（用户 11-25「把游戏界面开头那个 play 啥的界面删了」）② 机库齿轮打开设置，四个页签；开关生效、存档 ③ 兑换码错的 / 对的 / 再兑
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check
T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local TT = R.require(R.services.ReplicatedStorage:FindFirstChild("TechTree"))
local me = T.join("P1", 9701, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
T.leaveMenu()
R.run(1)
local C = T.C
print("① 进服：不出主菜单，直接是机库")
check(not (C.menuShown and C.menuShown()), "主菜单没出来")
check(C.hangarGui and C.hangarGui.Visible, "机库开着")
print("② 机库顶栏的齿轮打开设置")
local function find(root, name)
  for _, c in ipairs(root and root:GetDescendants() or {}) do if c.Name == name then return c end end
end
local sb = find(C.hangarGui, "SettingsBtn")
check(sb ~= nil, "机库顶栏有「设置」")
if sb then T.press(sb) end
R.run(0.3)
check(C.settingsShown and C.settingsShown(), "设置打开了")
local sg = C.settingsGui
for _, k in ipairs({ "main", "ctl", "ground", "air", "snd", "code" }) do check(find(sg, "Nav_" .. k) ~= nil, "导航 " .. k) end
check(find(sg, "Search") ~= nil and find(sg, "Drop_lang") ~= nil and find(sg, "Drop_ui") ~= nil, "搜索框、语言和界面比例下拉框")
-- 勾选：反转 Y（操作设置）
T.press(find(sg, "Nav_ctl"))
R.run(0.2)
local seg = find(sg, "Check_invY")
if seg then T.press(seg) end
R.run(1)
check(C.invertY == true, "反转 Y 生效")
local js = me:GetAttribute("Prefs")
check(type(js) == "string" and js:find("invY") ~= nil and js:find("true") ~= nil, "服务器存下了设置：" .. tostring(js))
check(P.data and P.data.prefs and P.data.prefs.invY == true, "存在存档里")
-- 用户 11-28「默认飞机不要准心控制吧 就键盘控制」：默认纯键盘；老存档（没有 pv）里的「鼠标瞄准」是当时的默认值，换成键盘；新存档照存的
check(C.airMouseAim == false, "固定翼默认纯键盘操纵（不是准心控制）")
me:SetAttribute("Prefs", '{"airAim":"mouse","sens":1}')
R.run(0.5)
check(C.airMouseAim == false, "老存档里的「鼠标瞄准」（当时的默认值）换成纯键盘")
R.run(1.5)   -- 换了新默认会马上存一次（带上 pv）：等它发完、服务器写回来
check(P.data and P.data.prefs and P.data.prefs.pv == 2 and P.data.prefs.airAim == "kb", "换成新默认以后存了一次（带上设置版本 pv）")
me:SetAttribute("Prefs", '{"airAim":"mouse","pv":2}')
R.run(0.5)
check(C.airMouseAim == true, "新存档里自己选的鼠标瞄准照旧")
C.setPref("airAim", "kb")
R.run(1)
-- 用户 11-28「设置里增加一个画质调整」：主要参数里「画质」；选了档 G.perfK 钉在那一档（自动画质不调），「低」关场景阴影；存档
T.press(find(sg, "Nav_main"))
R.run(0.2)
check(find(sg, "Drop_gfx") ~= nil, "主要参数里有「画质」下拉框")
C.setPref("gfx", "low")
R.run(1)
local Lt = R.services.Lighting
check(C.gfxK == 0.55 and C.perfK == 0.55 and Lt.GlobalShadows == false, string.format("画质「低」：画多细 %.2f、场景阴影 %s", C.perfK or -1, tostring(Lt.GlobalShadows)))
check(P.data and P.data.prefs and P.data.prefs.gfx == "low", "画质存进了存档")
C.setPref("gfx", "ultra")
R.run(0.5)
check(C.perfK == 1.2 and Lt.GlobalShadows == true, "画质「极高」：画多细 1.2、阴影开回来")
C.setPref("gfx", "auto")
R.run(0.5)
check(C.gfxK == nil, "画质「自动」：按帧率自己调")
-- 兑换码：错的、对的
print("③ 兑换码")
T.press(find(sg, "Nav_code"))
R.run(0.2)
local box = C.settingsRedeemBox
box.Text = "wrongcode"
T.press(find(sg, "RedeemBtn"))
R.run(0.5)
local res = find(sg, "RedeemRes")
check(res and res.Text:find("不对") ~= nil, "错的码：" .. tostring(res and res.Text))
R.run(2.2)
box.Text = "  ZhengYongShuo "
T.press(find(sg, "RedeemBtn"))
R.run(0.8)
check(res and res.Text:find("兑换成功") ~= nil, "对的码：" .. tostring(res and res.Text))
local t = G.treeOf(P)
local all, n = true, 0
for key in pairs(TT.byKey) do
  n = n + 1
  if not (TT.researched(t, key) and TT.owned(t, key)) then all = false end
end
check(all, "科技树 " .. n .. " 辆全部研究完、买下")
R.run(2.2)
T.press(find(sg, "RedeemBtn"))
box.Text = "zhengyongshuo"
T.press(find(sg, "RedeemBtn"))
R.run(0.8)
print("  再兑一次：", res and res.Text)
-- 关掉
T.press(find(sg, "Done"))
R.run(0.2)
check(not C.settingsShown(), "「完成」关掉")
print(T.summary and T.summary() or "")
