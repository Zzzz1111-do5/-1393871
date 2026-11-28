-- 金币充值（R 币买金币，Shop.lua / CoinShop.lua）：python3 tools/mock/run.py tools/mock/coinshop.lua
--   用户 11-28「你做个金币充值界面好了收robux」
--   ① 机库右上金币旁边的「+」打开充值页：五档（Config.CoinPacks）、现有金币；没上架（编号 0）的写「未上架」、点了不发购买
--   ② 填了编号的那一档：写价钱（R$），点「购买」服务器去弹 Roblox 的购买框（buyCoins）
--   ③ ProcessReceipt（G.shopReceipt）：付了钱的那一单金币到账、客户端金币数跟着变、弹「充值成功」；同一单再调不重复发；
--      不认得的产品、人不在这台服务器：NotProcessedYet；存档没写进去：退回刚加的、NotProcessedYet（Roblox 会再调）
--   ④ Esc 关
local T = dofile(MOCK_DIR .. "/common.lua")
local R, Enum = T.R, T.Enum
local check = T.check

T.wtMode = true
T.matchMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
G.Config.Match.wait = 600
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9575, true)
T.runUntil(function() return G.round ~= nil end, 30)
local P = G.P[me]
local C = T.C
T.leaveMenu()
T.runUntil(function() return G.rangeReady == true and T.findNamed("HangarGo") ~= nil end, 120, 1 / 10)
R.run(1)
local RS = R.services.ReplicatedStorage
local CfgC = R.require(RS:FindFirstChild("Config"))
local DEC = G.shopDecision

print("① 金币旁边的「+」打开充值页")
local plus = T.findNamed("CoinShopBtn")
check(plus ~= nil, "机库右上金币条上有「+」")
if plus then T.press(plus) R.run(0.4) end
local gui = C.coinShopGui
check(gui ~= nil and gui.Enabled and C.coinShopOpen(), "点「+」开了充值页")
local nPack, notListed = 0, 0
for _, p in ipairs(G.Config.CoinPacks) do
  local card = gui and gui:FindFirstChild("Pack_" .. p.key, true)
  if card then
    nPack = nPack + 1
    local b = card:FindFirstChild("Buy")
    if b and b.Text:find("未上架", 1, true) then notListed = notListed + 1 end
  end
end
check(nPack == #G.Config.CoinPacks and nPack == 5, "五档都在（" .. nPack .. "）")
check(notListed == nPack, "编号还是 0：都写「未上架」（" .. notListed .. "）")
local bal = gui and gui:FindFirstChild("Balance", true)
check(bal ~= nil and bal.Text:find("金币", 1, true) ~= nil, "写着现有多少金币：" .. tostring(bal and bal.Text))
local p0 = G.shopPrompted or 0
local b1 = gui:FindFirstChild("Pack_c1", true):FindFirstChild("Buy")
T.press(b1)
R.run(0.4)
check((G.shopPrompted or 0) == p0, "没上架的点了不发购买")

print("② 填了编号的那一档：写价钱，点了服务器弹购买框")
G.Config.CoinPacks[1].id = 777001
CfgC.CoinPacks[1].id = 777001
T.press(gui:FindFirstChild("Close", true))
R.run(0.2)
if plus then T.press(plus) R.run(0.4) end
b1 = gui:FindFirstChild("Pack_c1", true):FindFirstChild("Buy")
check(b1.Text:find("R$", 1, true) ~= nil and b1.Text:find("99", 1, true) ~= nil, "价钱写上了：" .. b1.Text)
T.press(b1)
R.run(0.4)
check((G.shopPrompted or 0) == p0 + 1, "点「购买」：服务器去弹 Roblox 的购买框（buyCoins）")

print("③ ProcessReceipt：到账一次、同一单不重复发、存档没写进去退回")
local saveNow0, canSave0 = G.saveNow, P.canSave
local saves = 0
G.saveNow = function() saves = saves + 1 return true end   -- 模拟器没有 DataStore：当作写进去了
P.canSave = true
local c0 = P.data.coins
local r1 = G.shopReceipt({ PlayerId = me.UserId, ProductId = 777001, PurchaseId = "buy-1", CurrencySpent = 99 })
R.run(0.3)
check(r1 == DEC.ok and P.data.coins == c0 + 10000 and saves == 1, string.format("付了钱：到账 1 万（%d → %d）、马上存档（%d 次）、回 PurchaseGranted", c0, P.data.coins, saves))
check(me:GetAttribute("Coins") == P.data.coins, "客户端的金币数跟着变（" .. tostring(me:GetAttribute("Coins")) .. "）")
check(#T.texts("充值成功") > 0, "弹「充值成功」")
local r2 = G.shopReceipt({ PlayerId = me.UserId, ProductId = 777001, PurchaseId = "buy-1", CurrencySpent = 99 })
check(r2 == DEC.ok and P.data.coins == c0 + 10000 and saves == 1, "同一单 Roblox 又调一次：不重复发（" .. P.data.coins .. "）")
check(G.shopReceipt({ PlayerId = me.UserId, ProductId = 123, PurchaseId = "buy-2" }) == DEC.later, "不认得的产品：NotProcessedYet")
check(G.shopReceipt({ PlayerId = 424242, ProductId = 777001, PurchaseId = "buy-3" }) == DEC.later, "人不在这台服务器：NotProcessedYet")
G.saveNow = function() return false end
local c1 = P.data.coins
local r4 = G.shopReceipt({ PlayerId = me.UserId, ProductId = 777001, PurchaseId = "buy-4" })
check(r4 == DEC.later and P.data.coins == c1 and P.data.rcpt["buy-4"] == nil, "存档没写进去：退回刚加的、不记这一单、NotProcessedYet（Roblox 会再调）")
G.saveNow = function() return true end
local r5 = G.shopReceipt({ PlayerId = me.UserId, ProductId = 777001, PurchaseId = "buy-4" })
check(r5 == DEC.ok and P.data.coins == c1 + 10000, "Roblox 再调同一单：这回写进去了、到账")
G.saveNow, P.canSave = saveNow0, canSave0
R.run(0.3)
check(bal.Text:find(tostring(math.floor(P.data.coins / 1000)), 1, true) ~= nil, "充值页上的余额跟着变：" .. bal.Text)

print("④ Esc 关")
T.tap(Enum.KeyCode.Escape)
R.run(0.2)
check(not gui.Enabled, "Esc 关了充值页")
G.Config.CoinPacks[1].id = 0
CfgC.CoinPacks[1].id = 0
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | ", 1, math.min(#R.errors, 3)))
T.summary()
