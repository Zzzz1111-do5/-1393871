-- 全面大战场——金币（用户 11-23：「把很多坦克飞机直升机搞成金币解锁吧 然后两边都可以用对方的载具 然后金币 pvp 或者打 pve 来……改枪配件也是需要解锁」）
--   存档 P.data：coins 金币、ownVeh 买过的载具、ownAtt 买过的配件（"枪.位.配件"）、pve 打通到第几关（Store.lua 读档时调 G.econFromSave）
--   写在玩家属性上给客户端（召唤点的机型卡片、改枪界面、部署界面）：Coins、OwnVeh（逗号隔开）、OwnAtt、PveCleared
--   载具（Config.Economy.veh）：价钱是 0 或不在表里的直接能开；别的买了才能召唤（Depots.lua 的 padSpawn 查 G.vehUnlocked）
--   配件：到了这把枪的解锁等级照旧白给；没到也能拿金币买（Config.AttPrice；Gunsmith.lua 整理配件时查 G.attOwned）
--   挣：一局打完按得分、输赢发（G.awardCoins，Round.lua 结算时调）；PvE 关卡打通另有奖励（Pve.lua 调 G.addCoins）
local RS = game:GetService("ReplicatedStorage")

local Economy = {}

function Economy.init(G)
  local Config = G.Config
  local E = Config.Economy
  local GM = require(RS:WaitForChild("GunMods"))

  local function setList(t)
    local out = {}
    for k in pairs(t or {}) do table.insert(out, k) end
    table.sort(out)
    return table.concat(out, ",")
  end
  local function publish(P)
    local d = P.data
    if not d then return end
    pcall(function()
      P.pl:SetAttribute("Coins", d.coins)
      P.pl:SetAttribute("OwnVeh", setList(d.ownVeh))
      P.pl:SetAttribute("OwnAtt", setList(d.ownAtt))
      P.pl:SetAttribute("PveCleared", d.pve or 0)
      P.pl:SetAttribute("EconAll", G.econAll == true)   -- 测试台全开：客户端的卡片不画锁
    end)
  end
  G.econPublish = publish

  -- 读档：没有金币字段的（新玩家、老存档）给开局的金币
  local function toSet(v, ok)
    local out = {}
    if type(v) == "table" then
      for k, x in pairs(v) do
        if type(k) == "string" and x == true and ok(k) then out[k] = true
        elseif type(x) == "string" and ok(x) then out[x] = true end
      end
    end
    return out
  end
  local function attKeyOk(k)
    local gun, slot, item = string.match(k, "^([%w_]+)%.([%w_]+)%.([%w_]+)$")
    return gun ~= nil and GM.unlockLv(gun, slot, item) ~= nil
  end
  function G.econFromSave(P, d)
    local D = P.data
    D.coins = math.max(0, math.floor(tonumber(d.coins) or E.startCoins))
    D.ownVeh = toSet(d.ownVeh, function(k) return Config.VehPrice(k) ~= nil end)
    D.ownAtt = toSet(d.ownAtt, attKeyOk)
    D.pve = math.max(0, math.floor(tonumber(d.pve) or 0))
    publish(P)
  end

  function G.coinsOf(P) return (P.data and P.data.coins) or 0 end
  -- 加 / 扣金币；why：给客户端的那一行字（nil 不提示）
  function G.addCoins(P, n, why, ...)
    local d = P.data
    if not d or n == 0 then return false end
    d.coins = math.max(0, d.coins + math.floor(n))
    publish(P)
    if why then G.msg(P.pl, (n > 0) and "good" or "info", why, math.abs(math.floor(n)), ...) end
    return true
  end
  local function save(P) if G.saveData then task.spawn(G.saveData, P) end end

  ---------------------------------------------------------------- 载具

  function G.vehUnlocked(P, id)
    if G.econAll then return true end   -- 测试台：载具全开（tools/mock、tools/test 的启动设的）
    local price = Config.VehPrice(id)
    if price == nil or price <= 0 then return true end
    local d = P.data
    return d ~= nil and d.ownVeh[id] == true
  end
  G.ACT.buyVeh = function(P, id)
    if type(id) ~= "string" then return end
    local price = Config.VehPrice(id)
    if not price or price <= 0 then return end
    local d = P.data
    if not d then G.msg(P.pl, "bad", "eco.notLoaded") return end
    if d.ownVeh[id] then return end
    if d.coins < price then G.msg(P.pl, "bad", "eco.poor", price - d.coins) return end
    d.coins -= price
    d.ownVeh[id] = true
    publish(P)
    G.msg(P.pl, "good", "eco.boughtVeh", { k = "veh." .. id }, price)
    save(P)
    G.pushOne(P)
  end

  ---------------------------------------------------------------- 配件

  function G.attOwned(P, gun, slot, item)
    local d = P.data
    return d ~= nil and d.ownAtt[gun .. "." .. slot .. "." .. item] == true
  end
  G.ACT.buyAtt = function(P, gun, slot, item)
    if type(gun) ~= "string" or type(slot) ~= "string" or type(item) ~= "string" then return end
    local lv = GM.unlockLv(gun, slot, item)
    if not lv then return end
    local d = P.data
    if not d then G.msg(P.pl, "bad", "eco.notLoaded") return end
    local key = gun .. "." .. slot .. "." .. item
    if d.ownAtt[key] then return end
    if G.gunLevel and G.gunLevel(P, gun) >= lv then return end   -- 等级已经到了：本来就能用
    local price = Config.AttPrice(lv)
    if price <= 0 then return end
    if d.coins < price then G.msg(P.pl, "bad", "eco.poor", price - d.coins) return end
    d.coins -= price
    d.ownAtt[key] = true
    publish(P)
    G.msg(P.pl, "good", "eco.boughtAtt", { k = "gm.item." .. item }, price)
    if G.gunPublish then G.gunPublish(P) end
    save(P)
  end

  ---------------------------------------------------------------- 挣

  -- 一局打完（Round.lua 结算，先于存档）：得分 × perScore + 赢 / 输；PvE 模式（Pve.lua）照这个算一份，打通关卡另外加
  function G.awardCoins(P, won)
    if not P.data then return end
    local n = math.floor((P.roundXp or 0) * E.perScore) + (won and E.win or E.lose)
    if n > 0 then G.addCoins(P, n, "eco.round") end
  end
end

return Economy
