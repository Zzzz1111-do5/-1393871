-- Roblox全面大战场——存档：经验、军衔、总击杀 / 阵亡 / 胜场 / 场次（DataStore；读不到就这一次不存）
local DataStoreService = game:GetService("DataStoreService")

local Store = {}

function Store.init(G)
  local Config = G.Config
  local store = nil
  pcall(function() store = DataStoreService:GetDataStore(Config.SaveKey) end)

  local function key(P) return "u" .. P.pl.UserId end

  -- 三步操作卡的种类（Coach.lua 的 CARDS）：客户端发来别的名字不收
  local SEEN = { veh = true, lcac = true, jet = true, heli = true, uav = true, ship = true, fort = true, arty = true }
  local function seenAttr(P)   -- 存在玩家属性上（逗号隔开），客户端直接读，不用等状态推送
    local list = {}
    for k in pairs((P.data and P.data.seen) or P.seenEarly or {}) do table.insert(list, k) end
    table.sort(list)
    pcall(function() P.pl:SetAttribute("Seen", table.concat(list, ",")) end)
  end
  -- 客户端：这种载具的三步卡看过了（关掉或看够了几秒）
  G.ACT.seen = function(P, kind)
    if type(kind) ~= "string" or not SEEN[kind] then return end
    if P.data then
      if P.data.seen[kind] then return end
      P.data.seen[kind] = true
    else
      P.seenEarly = P.seenEarly or {}
      P.seenEarly[kind] = true
    end
    seenAttr(P)
  end

  function G.loadData(P)
    local raw, ok = nil, false
    if store then
      for _ = 1, 3 do
        ok, raw = pcall(function() return store:GetAsync(key(P)) end)
        if ok then break end
        task.wait(1)
      end
    end
    if G.P[P.pl] ~= P then return end
    local d = (ok and type(raw) == "table") and raw or {}
    P.data = {
      xp = math.max(0, tonumber(d.xp) or 0), kills = tonumber(d.kills) or 0, deaths = tonumber(d.deaths) or 0,
      wins = tonumber(d.wins) or 0, games = tonumber(d.games) or 0, caps = tonumber(d.caps) or 0,
      seen = {},
    }
    -- 改枪（Gunsmith.lua）：每把枪装的配件、存的方案、枪械经验；读档前这一次进服已经改过的也并进来
    if G.gunsFromSave then
      P.data.guns, P.data.gxp = G.gunsFromSave(d)
      G.gunsMergeEarly(P)
    end
    -- 新手三步操作卡看过哪几种（Coach.lua）：只留认得的名字；读档前这一次进服已经看过的也并进来
    if type(d.seen) == "table" then
      for k, v in pairs(d.seen) do if SEEN[k] and v == true then P.data.seen[k] = true end end
    end
    for k in pairs(P.seenEarly or {}) do P.data.seen[k] = true end
    P.seenEarly = nil
    if G.econFromSave then G.econFromSave(P, d) end   -- 金币、买过的载具和配件、PvE 打到第几关（Economy.lua）
    seenAttr(P)
    P.canSave = ok and store ~= nil
    if G.gunPublish then G.gunPublish(P) end
    P.xp = P.data.xp
    P.rank = Config.RankOf(P.xp)
    G.pushOne(P)
  end

  function G.saveData(P)
    if not store or not P.canSave or not P.data then return end
    local d = P.data
    pcall(function() store:SetAsync(key(P), d) end)
  end

  -- 一局结束：得分记成经验，战绩累计，升军衔提示，存档
  function G.awardXp(P, won)
    local d = P.data
    if not d then return end
    local gain = math.max(0, math.floor(P.roundXp or 0))
    d.xp += gain
    d.kills += P.kills
    d.deaths += P.deaths
    d.caps += P.caps
    d.games += 1
    if won then d.wins += 1 end
    local old = P.rank or 1
    P.xp = d.xp
    P.rank = Config.RankOf(d.xp)
    G.msg(P.pl, "good", "ui.xp", gain)
    if P.rank > old then G.msg(P.pl, "good", "ui.rankUp", { k = "rank." .. P.rank }) end
    task.spawn(G.saveData, P)
  end

  function G.saveAll()
    for _, P in pairs(G.P) do task.spawn(G.saveData, P) end
    task.wait(2)
  end
end

return Store
