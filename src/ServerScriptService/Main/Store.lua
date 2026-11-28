-- 全面大战场——存档（DataStore）：经验、军衔、战绩、改枪、设置、金币（Economy.lua）、科技树（研究 / 购买 / 阵容 / 改装 / 乘员、兑换过的码，Tech.lua）
--   用户 11-26「账号的载具解锁要能保留」——原来丢档的几处（tools/mock/econ.lua 都复现过、一直测着）：
--   ① Studio 没开「允许访问 API 服务」（或地点还没发布）：读档失败，这一次进服整个不存档，一声不吭——
--      现在输出里 warn 写清楚为什么、怎么开，屏幕上也提示；这一次的进度留在内存里（这台服务器上退出再进还在），
--      读档失败时用的那份临时档永远不写回 DataStore（不拿空档盖旧档）
--   ② 每个动作（换系、研究、买、换阵容……）都马上写一次：Roblox 同一个键 6 秒才能写一次、多的排队，关服（BindToClose）只等 2 秒，
--      排在后面的（比如刚兑换的码）就没写进去——现在一个人同一时间只有一个写在跑，写完还有改动再写（两次至少隔 Config.Save.gap 秒）；
--      离开、关服马上写最后一次，关服等全写完（最多 closeWait 秒）；另外每 auto 秒看一次，变了就存；写失败 warn、过一会儿再试
--   ③ 读档只留认得的字段，认不得的扔掉、再一存就没了（新版本加的字段到了老服务器上）——现在认不得的原样留着
--   每次写记一个版本号 rev：读档以后别的服务器又写过（换服太快，上一台服务器的最后一次写排在后面），就把两边解锁的车、兑换过的码合起来再写
local DataStoreService = game:GetService("DataStoreService")
local Http = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Store = {}

function Store.init(G)
  local Config = G.Config
  local SV = Config.Save or {}
  local GAP, AUTO, CLOSE_WAIT = SV.gap or 7, SV.auto or 60, SV.closeWait or 25
  local now = os.clock
  local studio = false
  pcall(function() studio = RunService:IsStudio() end)
  local store, storeErr = nil, nil
  do
    local ok, err = pcall(function() store = DataStoreService:GetDataStore(Config.SaveKey) end)
    if not ok then store, storeErr = nil, tostring(err) end
  end

  local function key(P) return "u" .. P.pl.UserId end

  -- 存不了档：输出里说一次为什么、怎么办（Studio 里最常见的是没开 API 服务）
  local warnedOff = false
  local function warnOff(why)
    if warnedOff then return end
    warnedOff = true
    warn("[存档] 读不到存档，这一次存不了档：" .. tostring(why))
    warn("[存档] 这一次进服的进度只留在内存里（这台服务器上退出再进还在），停止测试 / 关服就没了；DataStore 里原来的档不动（不会被空档盖掉）")
    if studio then
      warn("[存档] Studio 里要存档：先「文件 → 发布到 Roblox」，再「主页 → 游戏设置 → 安全」打开「允许 Studio 访问 API 服务」（Enable Studio Access to API Services），然后重新开始测试")
    end
  end

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

  -- 设置（客户端 Settings.lua，用户 11-25「那个设置界面不好看 重做」）：灵敏度、反转 Y、视野、镜头晃动、音量、车组语音——
  --   只收认得的键、数字夹在范围里；存在 P.data.prefs，给客户端写玩家属性 Prefs（JSON）；改了 10 秒后存一次档（连着拖滑块只存一次）
  local PREFS = { sens = { 0.25, 2.5 }, aim = { 0.25, 2.0 }, fov = { 60, 90 }, fovAir = { 60, 90 }, vol = { 0, 1 }, ui = { 0.85, 1.3 }, gamma = { -0.1, 0.1 },
    invY = true, shake = true, voice = true, lang = { s = { [""] = true, zh = true, en = true } },
    airAim = { s = { mouse = true, kb = true } }, camRoll = { 0, 1 }, autoGear = true }   -- 空战：操纵方式、镜头滚转、自动收起落架
  local function prefsAttr(P)
    local t = (P.data and P.data.prefs) or P.prefsEarly or {}
    local ok, js = pcall(function() return Http:JSONEncode(t) end)
    if ok then pcall(function() P.pl:SetAttribute("Prefs", js) end) end
  end
  local function cleanPrefs(src)
    local out = {}
    if type(src) ~= "table" then return out end
    for k, rule in pairs(PREFS) do
      local v = src[k]
      if rule == true then
        if type(v) == "boolean" then out[k] = v end
      elseif rule.s then   -- 几个字里挑一个
        if type(v) == "string" and rule.s[v] then out[k] = v end
      elseif type(v) == "number" and v == v then
        out[k] = math.clamp(v, rule[1], rule[2])
      end
    end
    return out
  end
  G.ACT.prefs = function(P, t)
    local c = cleanPrefs(t)
    if P.data then P.data.prefs = c else P.prefsEarly = c end
    prefsAttr(P)
    if P.data and not P.prefsSaveQ then
      P.prefsSaveQ = true
      task.delay(10, function()
        P.prefsSaveQ = nil
        if G.P[P.pl] == P then G.saveData(P) end
      end)
    end
  end

  ---------------------------------------------------------------- 写档

  -- 这一刻整份存档的拷贝（JSON 来回一遍：写的时候、留在内存里的都跟后来的改动分开）
  local function snap(P)
    local ok, js = pcall(function() return Http:JSONEncode(P.data) end)
    if not ok then return nil, nil, js end
    local ok2, t = pcall(function() return Http:JSONDecode(js) end)
    if not ok2 then return nil, nil, t end
    return t, js
  end
  -- 两份档里解锁的车（科技树研究完、买下）、兑换过的码合起来（只加不减）；dst 有变化返回 true
  local function mergeUnlocks(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return false end
    local any = false
    local st = type(src.tree) == "table" and src.tree or nil
    if st then
      dst.tree = type(dst.tree) == "table" and dst.tree or {}
      for _, f in ipairs({ "res", "own" }) do
        if type(st[f]) == "table" then
          dst.tree[f] = type(dst.tree[f]) == "table" and dst.tree[f] or {}
          for k, v in pairs(st[f]) do
            if v == true and type(k) == "string" and dst.tree[f][k] ~= true then
              dst.tree[f][k] = true
              any = true
            end
          end
        end
      end
    end
    if type(src.codes) == "table" then
      dst.codes = type(dst.codes) == "table" and dst.codes or {}
      for k, v in pairs(src.codes) do
        if type(k) == "string" and dst.codes[k] == nil then
          dst.codes[k] = v
          any = true
        end
      end
    end
    return any
  end
  G.saveMerge = mergeUnlocks   -- 测试用

  -- 写一次（UpdateAsync）：存档上的版本号比这一次读档时的新（别的服务器后来又写过）——两边解锁的车、码合起来再写
  local function writeOnce(P, data)
    local merged = false
    local base = P.revBase or 0
    local ok, err = pcall(function()
      store:UpdateAsync(key(P), function(old)
        local orev = (type(old) == "table" and tonumber(old.rev)) or 0
        if orev > base and mergeUnlocks(data, old) then merged = true end
        data.rev = math.max(orev, base) + 1
        return data
      end)
    end)
    if ok then
      P.revBase = data.rev
      if merged and P.data and mergeUnlocks(P.data, data) then
        warn("[存档] " .. tostring(P.pl and P.pl.Name) .. "：别的服务器在这之后也写过存档，两边解锁的载具合在一起了")
        if G.treeReload then G.treeReload(P) end   -- 科技树重新整理、写给客户端（Tech.lua）
      end
    end
    return ok, err
  end

  local memo = {}   -- [UserId] = { data = 退出时整份存档的拷贝, rev = 它基于的版本号, ok = 那一次读档成功没有 }：这台服务器上退出再进不丢
  local W = {}      -- [P] = { busy 正在写, dirty 有新改动, final 离开 / 关服（不等间隔）, last 上次开始写的时刻, js 上次写进去的 JSON }
  local function stOf(P)
    local s = W[P]
    if not s then
      s = { last = -1e9 }
      W[P] = s
    end
    return s
  end
  G.saveState = function(P) return W[P] end   -- 测试用
  local function writer(P)
    local s = stOf(P)
    if s.busy then return end
    s.busy = true
    local fails = 0
    while s.dirty and P.data and P.canSave and store do
      while not s.final and now() - s.last < GAP do task.wait(0.25) end   -- 两次写至少隔 GAP 秒；离开 / 关服不等
      s.dirty = false
      local data, js, e = snap(P)
      if not data then
        warn("[存档] " .. P.pl.Name .. " 的存档转不成 JSON，这次没写：" .. tostring(e))
        break
      end
      if js ~= s.js then   -- 跟上次写进去的一样就不写
        s.last = now()
        local ok, err = writeOnce(P, data)
        if ok then
          s.js, fails = js, 0
          if s.final and memo[P.pl.UserId] then memo[P.pl.UserId].rev = P.revBase end
        else
          fails += 1
          s.dirty = true
          if fails == 1 then
            warn("[存档] " .. P.pl.Name .. " 的存档没写进去（" .. tostring(err) .. "），过一会儿再试")
            if not s.final then G.msg(P.pl, "bad", "save.fail") end
          end
          if fails >= 3 then break end   -- 这一轮不试了：定时自动存、离开时再来
          if s.final then task.wait(1) end
        end
      end
    end
    s.busy = false
    if P.leaving and not s.dirty then W[P] = nil end
  end

  -- 要存档（各模块改了东西都调这个，马上返回）：同一个人合成一次写；人在离开（P.leaving）就马上写最后一次，并在内存里留一份
  function G.saveData(P)
    if not P or not P.data then return end
    if P.leaving and P.pl then
      local data = snap(P)
      if data then memo[P.pl.UserId] = { data = data, rev = P.revBase or 0, ok = P.canSave == true } end
    end
    if not store or not P.canSave then return end
    local s = stOf(P)
    s.dirty = true
    if P.leaving then s.final = true end
    if not s.busy then task.spawn(writer, P) end
  end
  -- 离开：Round.lua 先发 left 再调 G.saveData，这里先记下「在离开」——那一次就是最后一次，马上写
  G.on("left", function(P) P.leaving = true end)

  -- 定时自动存：存档跟上次写进去的不一样（改了没调存档的、上一轮没写进去的）就存
  task.spawn(function()
    while true do
      task.wait(AUTO)
      for _, P in pairs(G.P) do
        if P.data and P.canSave and store and not P.leaving then
          local s = W[P]
          if not (s and s.busy) then
            local ok, js = pcall(function() return Http:JSONEncode(P.data) end)
            if (s and s.dirty) or (ok and js ~= (s and s.js)) then G.saveData(P) end
          end
        end
      end
    end
  end)

  ---------------------------------------------------------------- 读档

  function G.loadData(P)
    local raw, ok, err = nil, false, storeErr or "拿不到 DataStore"
    if store then
      for i = 1, 3 do
        local okA, r = pcall(function() return store:GetAsync(key(P)) end)
        if okA then
          ok, raw = true, r
          break
        end
        err = tostring(r)
        if i < 3 then task.wait(i) end
      end
    end
    if G.P[P.pl] ~= P then return end
    if ok and raw ~= nil and type(raw) ~= "table" then   -- 存档里不是表：当成读不到，不拿新档盖掉它
      ok, err = false, "存档格式不对（" .. typeof(raw) .. "）"
    end
    local m = memo[P.pl.UserId]
    local d
    if ok then
      d = raw or {}
      P.revBase = tonumber(d.rev) or 0
      if m and m.ok and (m.rev or 0) >= P.revBase then
        d, P.revBase = m.data, m.rev or 0   -- 这台服务器上刚退出的那份更新（最后一次写还在路上，或读到的是 Roblox 缓存的旧值）
      elseif m and not m.ok then
        mergeUnlocks(d, m.data)   -- 上次读档失败、只在内存里玩的那份：解锁的车、兑换过的码并进来
      end
    else
      d = (m and m.data) or {}   -- 读不到：这台服务器上退出前的进度接着用（只在内存里）
      P.revBase = (m and m.rev) or 0
      warnOff(err)
    end
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
    P.data.prefs = P.prefsEarly or cleanPrefs(d.prefs)   -- 设置：读档前这一次进服已经改过的为准
    P.prefsEarly = nil
    prefsAttr(P)
    if G.econFromSave then G.econFromSave(P, d) end   -- 金币、买过的载具和配件、PvE 打到第几关（Economy.lua）；科技树、兑换过的码（Tech.lua）
    -- 认不得的字段原样留着（新版本服务器加的、以后的功能用的）：不然这里一存就把它们抹掉了
    for k, v in pairs(d) do
      if type(k) == "string" and k ~= "rev" and P.data[k] == nil then P.data[k] = v end
    end
    seenAttr(P)
    P.canSave = ok and store ~= nil
    if not P.canSave then G.msg(P.pl, "bad", "save.off") end
    if G.gunPublish then G.gunPublish(P) end
    P.xp = P.data.xp
    P.rank = Config.RankOf(P.xp)
    G.pushOne(P)
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
    G.saveData(P)
  end

  -- 关服（init.server.lua 的 BindToClose）：每个人马上写最后一次，等到全写完（最多 CLOSE_WAIT 秒；Roblox 给 30 秒）
  function G.saveAll()
    for _, P in pairs(G.P) do
      P.leaving = true
      G.saveData(P)
    end
    local t0 = now()
    while now() - t0 < CLOSE_WAIT do
      local busy = false
      for _, s in pairs(W) do
        if s.busy then busy = true break end   -- 写了三次都失败、放弃了的不等
      end
      if not busy then break end
      task.wait(0.2)
    end
  end
end

return Store
