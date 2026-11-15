-- Roblox全面大战场——存档：经验、军衔、总击杀 / 阵亡 / 胜场 / 场次（DataStore；读不到就这一次不存）
local DataStoreService = game:GetService("DataStoreService")

local Store = {}

function Store.init(G)
  local Config = G.Config
  local store = nil
  pcall(function() store = DataStoreService:GetDataStore(Config.SaveKey) end)

  local function key(P) return "u" .. P.pl.UserId end

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
    }
    P.canSave = ok and store ~= nil
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
