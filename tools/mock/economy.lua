-- 金币（模拟器；用户 11-23：「把很多坦克飞机直升机搞成金币解锁吧 然后两边都可以用对方的载具……改枪配件也是需要解锁」）：
--   python3 tools/mock/run.py tools/mock/economy.lua
--   ① 新玩家：开局金币、玩家属性
--   ② 两边的型号都能选：攻方的召唤点上有美军的坦克、飞机，守方的有解放军的
--   ③ 没买的型号召唤不了（服务器挡）；不要钱的照常；客户端卡片上画着锁和价钱
--   ④ 买：金币够就买下、存进 OwnVeh；不够不让买；买了能召唤
--   ⑤ 一局打完按得分、输赢发金币
--   ⑥ 配件：没到等级拿金币买了就能装；没买的照旧换成默认
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.econAll = false   -- 测试台默认载具全开（rbx.lua）：这里测的就是解锁
G.Config.Economy.infinite = false   -- 现在 Config 里开着无限金币（用户 11-24）：①～⑦ 测的是正常扣钱，⑧ 再打开测
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9501, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
T.runUntil(function() return P.data ~= nil end, 10)
R.run(1)
local C = T.C
T.leaveMenu()
local E = G.Config.Economy

print("① 新玩家的金币")
check(P.data and P.data.coins == E.startCoins, "开局 " .. E.startCoins .. " 金币（" .. tostring(P.data and P.data.coins) .. "）")
check(me:GetAttribute("Coins") == E.startCoins, "玩家属性 Coins 一样")
check(me:GetAttribute("OwnVeh") == "", "还没买过载具")

print("② 两边的型号都能选")
local atkModels = {}
for _, id in ipairs(G.vehModels("atk")) do atkModels[id] = true end
check(atkModels.m1a2 and atkModels.f35 and atkModels.ah64e and atkModels.ztz99a, "攻方能选 M1A2、F-35、阿帕奇（也有自己的 99A）")
local defModels = {}
for _, id in ipairs(G.vehModels("def")) do defModels[id] = true end
check(defModels.ztz99a and defModels.j20 and defModels.z10, "守方能选 99A、歼-20、直-10")
check(not atkModels.ddg125, "舰艇还是各用各的（攻方没有美军驱逐舰）")
local pad = nil
for _, p in ipairs(G.pads) do
  if p.team == "atk" and p.kind == "veh" and p.summon and not p.sea then
    for _, id in ipairs(p.vids) do if id == "m1a2" then pad = p end end
  end
end
if not pad then
  for _, p in ipairs(G.pads) do
    if p.team == "atk" and p.kind == "veh" and p.summon then
      for _, id in ipairs(p.vids) do if id == "m1a2" then pad = p end end
    end
  end
end
check(pad ~= nil, "攻方的地面召唤位上有 M1A2")

print("③ 没买的召唤不了")
T.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 10)
T.act("deploy", {}, "barge")
T.runUntil(function() return P.alive and me.Character ~= nil end, 10)
R.run(1)
local msgs = {}
local m0 = G.msg
G.msg = function(pl, kind, key, ...) if pl == me then table.insert(msgs, key) end return m0(pl, kind, key, ...) end
local function spawned(vid)
  for _, e in ipairs(G.vehicles or {}) do if e.padId == pad.id and e.alive and e.vid == vid then return e end end
  for _, e in ipairs(G.vehicles or {}) do if e.padId == pad.id and e.alive then return e end end
  return nil
end
if pad then
  T.padVid[pad] = "m1a2"
  local e = T.usePad(me, pad)
  check(e == nil, "M1A2（" .. G.Config.VehPrice("m1a2") .. " 金币）没买：没生成")
  local card = T.findNamed("Pick_m1a2")
  check(card ~= nil and card:FindFirstChild("CoinTag") ~= nil, "客户端卡片上画着金币锁（" .. tostring(card and card:FindFirstChild("CoinTag") and card.CoinTag.Text) .. "）")
  local free = T.findNamed("Pick_ztz96")
  check(free ~= nil and free:FindFirstChild("CoinTag") == nil, "96 式不要钱：没有锁")
  R.as("client", function() if C.closePick then C.closePick() end end)
  local seenNeed = false
  for _, k in ipairs(msgs) do if k == "eco.needVeh" then seenNeed = true end end
  -- 直接发 padSpawn（绕过卡片）：服务器照样挡
  T.act("padSpawn", pad.id, false, "m1a2")
  R.run(0.6)
  for _, k in ipairs(msgs) do if k == "eco.needVeh" then seenNeed = true end end
  check(seenNeed and spawned("m1a2") == nil, "服务器挡住了（eco.needVeh）")
end

print("④ 买")
G.ACT.buyVeh(P, "m1a2")   -- 3000：开局 1500 不够
check(not (P.data.ownVeh.m1a2) and P.data.coins == E.startCoins, "金币不够：没买成")
local poor = false
for _, k in ipairs(msgs) do if k == "eco.poor" then poor = true end end
check(poor, "提示金币不够（eco.poor）")
G.ACT.buyVeh(P, "m1a1")   -- 1500：正好
check(P.data.ownVeh.m1a1 == true and P.data.coins == E.startCoins - G.Config.VehPrice("m1a1"), "买下 M1A1（剩 " .. P.data.coins .. "）")
R.run(0.3)
check((me:GetAttribute("OwnVeh") or ""):find("m1a1", 1, true) ~= nil, "OwnVeh 里有 m1a1")
if pad then
  P.padT = 0
  T.padVid[pad] = "m1a1"
  local e = T.usePad(me, pad)
  check(e ~= nil, "买了：召唤出来了")
  if e then G.removeEnt(e) end
end

print("⑤ 一局打完发金币")
local c0 = P.data.coins
P.roundXp = 1000
G.awardCoins(P, true)
check(P.data.coins - c0 == math.floor(1000 * E.perScore) + E.win, string.format("赢了、1000 分：+%d 金币", P.data.coins - c0))
local c1 = P.data.coins
P.roundXp = 300
G.awardCoins(P, false)
check(P.data.coins - c1 == math.floor(300 * E.perScore) + E.lose, string.format("输了、300 分：+%d 金币", P.data.coins - c1))

print("⑥ 配件：等级没到拿金币买")
local GM = R.require(R.services.ReplicatedStorage:FindFirstChild("GunMods"))
check(G.gunLevel(P, "m4") == 1, "M4 一级")
G.ACT.gunBuild(P, "m4", { muzzle = "sup_socom" })
check(G.gunBuild(P, "m4").muzzle ~= "sup_socom", "SOCOM 消音器（7 级）没买：装不上")
G.addCoins(P, 2000)
local before = P.data.coins
local price = G.Config.AttPrice(GM.unlockLv("m4", "muzzle", "sup_socom"))
G.ACT.buyAtt(P, "m4", "muzzle", "sup_socom")
check(P.data.coins == before - price, "买消音器：-" .. price .. " 金币")
check((me:GetAttribute("OwnAtt") or ""):find("m4.muzzle.sup_socom", 1, true) ~= nil, "OwnAtt 里有它")
P.gunT = 0
G.ACT.gunBuild(P, "m4", { muzzle = "sup_socom", mag = "mag_drum" })
local b = G.gunBuild(P, "m4")
check(b.muzzle == "sup_socom", "买了：装上了")
check(b.mag ~= "mag_drum", "没买的弹鼓（14 级）还是装不上")
G.msg = m0

print("⑦ 客户端：金币牌子")
R.run(0.5)
local badge = me.PlayerGui:FindFirstChild("Coins") and me.PlayerGui.Coins:FindFirstChild("Badge")
local amount = badge and badge:FindFirstChild("Amount")
check(amount ~= nil and amount.Text:find(tostring(P.data.coins % 1000), 1, true) ~= nil, "牌子上写着现在的金币（" .. tostring(amount and amount.Text) .. "）")
print("⑧ 无限金币（Config.Economy.infinite，用户 11-24「给我先设置成无限金币」）")
E.infinite = true
G.econPublish(P)
R.run(0.5)
check(me:GetAttribute("CoinsInf") == true and (me:GetAttribute("Coins") or 0) >= 1e8, "玩家属性：CoinsInf、Coins 是个大数（" .. tostring(me:GetAttribute("Coins")) .. "）")
check(amount ~= nil and amount.Text:find("∞", 1, true) ~= nil, "牌子上写 ∞（" .. tostring(amount and amount.Text) .. "）")
P.data.coins = 0
G.ACT.buyVeh(P, "m1a2")
check(P.data.ownVeh.m1a2 == true and P.data.coins == 0, "一个金币没有也买得下 M1A2，存档里的金币不动")
G.ACT.buyAtt(P, "m4", "mag", "mag_drum")
check((me:GetAttribute("OwnAtt") or ""):find("m4.mag.mag_drum", 1, true) ~= nil and P.data.coins == 0, "配件也能买（弹鼓）")
E.infinite = false
G.econPublish(P)
R.run(0.3)
check(me:GetAttribute("CoinsInf") == false and me:GetAttribute("Coins") == 0, "关掉以后回到存档里的真金币")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
