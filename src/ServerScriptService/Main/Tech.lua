-- 全面大战场（服务器）——科技树：研究、购买、出击阵容、出击（用户 11-25：「从1960到现代的战机和坦克 科技树」「再去做一个中 德 美 日 俄系」
--   「不要让玩家拿枪之类的了 就跟战雷完全一样 不要让玩家作为个体活动」）
--   存档 P.data.tree：res 研究完的、own 买下的、rp[key] 攒着的研究点、cur[系:树] 正在研究的、lineup[系] 出击阵容（最多 5 辆）、nat 现在用哪个系、
--     free[系] 没处放的研究点（研究完多出来的、没选研究目标时挣的）
--   给客户端：玩家属性 Tree（JSON，变了才写）；动作（客户端 Act）：treeResearch / treeBuy / treeLineup / treeNat / deployVeh
--   挣研究点：一局结束按得分（G.treeAward，Round.lua 结算时调）；出车时记下这一局用过哪棵树，研究点分给用过的树正在研究的那辆
--   出击（deployVeh）：从出击阵容里挑一辆，人直接坐进车里 / 飞机里出现在自己基地（不步行：Config.Wt.noInfantry）；车没了回出击界面
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")

local Tech = {}

function Tech.init(G)
  local Config = G.Config
  local now = os.clock
  local TT = require(RS:WaitForChild("TechTree"))
  local VD = require(RS:WaitForChild("VehDefs"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local WM = require(RS:WaitForChild("WtMods"))   -- 每辆车的改装（研究点逐项研究，效果真的生效）
  local WC = require(RS:WaitForChild("WtCrew"))   -- 乘员（阵容每个位置一组，攒经验、点技能）
  local W = Config.Wt or {}
  local LINEUP = W.lineup or 5

  local function save(P) if G.saveData then task.spawn(G.saveData, P) end end
  -- mods[车] = { done = { 改装 = true }, cur = 正在研究的改装, rp = 攒在它上面的研究点 }
  --   crew[系]["位置"] = { xp = 乘员经验, sk = { 技能 = 级 } }（位置写成字符串：JSON 不认有空洞的数组）
  local function blank() return { res = {}, own = {}, rp = {}, cur = {}, lineup = {}, nat = "cn", free = {}, mods = {}, crew = {} } end
  local function T(P)
    local d = P.data
    if not d then return nil end
    d.tree = d.tree or blank()
    return d.tree
  end
  G.treeOf = T
  -- 第一次玩（阵容空着）：每棵树白送的那几辆放进阵容
  local function defaultLineup(t, nat)
    local out = {}
    for _, br in ipairs(TT.BRANCHES) do
      for _, it in ipairs(TT.list[nat][br]) do
        if it.free and #out < LINEUP then table.insert(out, it.key) end
      end
    end
    t.lineup[nat] = out
    return out
  end
  local function publish(P)
    local t = T(P)
    if not t or not P.pl then return end
    local ok, s = pcall(function() return Http:JSONEncode(t) end)
    if ok then P.pl:SetAttribute("Tree", s) end
  end
  G.treePublish = publish

  -- 读档：只留认得的 key
  local ef = G.econFromSave
  G.econFromSave = function(P, d)
    if ef then ef(P, d) end
    local src = (type(d) == "table" and type(d.tree) == "table") and d.tree or {}
    local t = blank()
    t.nat = TT.NAT[src.nat] and src.nat or "cn"
    for _, f in ipairs({ "res", "own" }) do
      for k, v in pairs(type(src[f]) == "table" and src[f] or {}) do if TT.byKey[k] and v == true then t[f][k] = true end end
    end
    for k, v in pairs(type(src.rp) == "table" and src.rp or {}) do
      if TT.byKey[k] and type(v) == "number" and v > 0 then t.rp[k] = math.floor(v) end
    end
    for k, v in pairs(type(src.cur) == "table" and src.cur or {}) do
      if type(k) == "string" and TT.byKey[v] then t.cur[k] = v end
    end
    for _, nat in ipairs(TT.NATIONS) do
      local f = type(src.free) == "table" and tonumber(src.free[nat]) or nil
      if f and f > 0 then t.free[nat] = math.floor(f) end
      local L = type(src.lineup) == "table" and src.lineup[nat]
      if type(L) == "table" then
        local out = {}
        for _, k in ipairs(L) do
          if TT.byKey[k] and TT.byKey[k].nat == nat and TT.owned(t, k) and #out < LINEUP then table.insert(out, k) end
        end
        t.lineup[nat] = out
      end
    end
    for k, m in pairs(type(src.mods) == "table" and src.mods or {}) do   -- 改装：只留认得的车、认得的改装
      local it = TT.byKey[k]
      if it and type(m) == "table" then
        local o = { done = {}, rp = 0 }
        for mk, v in pairs(type(m.done) == "table" and m.done or {}) do if v == true and WM.get(it, mk) then o.done[mk] = true end end
        if type(m.cur) == "string" and WM.canResearch(it, o.done, m.cur) then o.cur = m.cur end
        if type(m.rp) == "number" and m.rp > 0 then o.rp = math.floor(m.rp) end
        t.mods[k] = o
      end
    end
    for _, nat in ipairs(TT.NATIONS) do   -- 乘员：只留认得的技能、级数在范围里；点数超了（改过规则）就清零重点
      local cs = type(src.crew) == "table" and type(src.crew[nat]) == "table" and src.crew[nat] or {}
      local out = {}
      for i = 1, LINEUP do
        local c = cs[tostring(i)]
        if type(c) == "table" then
          local o = { xp = (type(c.xp) == "number" and c.xp > 0) and math.floor(c.xp) or 0, sk = {} }
          for _, s in ipairs(WC.SKILLS) do
            local v = type(c.sk) == "table" and tonumber(c.sk[s.key]) or nil
            if v and v >= 1 then o.sk[s.key] = math.min(WC.MAXLV, math.floor(v)) end
          end
          if WC.free(o) < 0 then o.sk = {} end
          out[tostring(i)] = o
        end
      end
      t.crew[nat] = out
    end
    P.data.tree = t
    publish(P)
  end

  -- 研究点记到一辆上；够了就研究完，多出来的进这个系的 free
  local function addRp(P, key, n)
    local t = T(P)
    local it = TT.byKey[key]
    if not t or not it or n <= 0 then return end
    if TT.researched(t, key) then
      t.free[it.nat] = (t.free[it.nat] or 0) + n
      return
    end
    t.rp[key] = (t.rp[key] or 0) + math.floor(n)
    if t.rp[key] >= it.rp then
      local over = t.rp[key] - it.rp
      t.rp[key] = nil
      t.res[key] = true
      t.cur[it.nat .. ":" .. it.branch] = nil
      if over > 0 then t.free[it.nat] = (t.free[it.nat] or 0) + over end
      if P.pl then G.msg(P.pl, "good", "tree.done", it.name) end
    end
  end
  G.treeAddRp = addRp   -- 测试用

  -- 改装（WtMods）：研究点记到这辆车正在研究的那项上（没选就自动挑下一项）；够了就装上、多出来的接着给下一项
  local function modsOf(t, key)
    t.mods = t.mods or {}
    local m = t.mods[key]
    if not m then
      m = { done = {}, rp = 0 }
      t.mods[key] = m
    end
    return m
  end
  local function addModRp(P, key, n)
    local t = T(P)
    local it = TT.byKey[key]
    if not t or not it or n <= 0 then return 0 end
    local m = modsOf(t, key)
    local used = 0
    for _ = 1, 20 do
      if not (m.cur and WM.canResearch(it, m.done, m.cur)) then m.cur = WM.nextKey(it, m.done) m.rp = 0 end
      if not m.cur or n <= 0 then break end
      local need = WM.cost(it, WM.get(it, m.cur)) - (m.rp or 0)
      if n < need then
        m.rp = (m.rp or 0) + math.floor(n)
        used += n
        n = 0
      else
        n -= need
        used += need
        m.done[m.cur] = true
        local mm = WM.get(it, m.cur)
        if P.pl and mm then G.msg(P.pl, "good", "tree.modDone", it.name, mm.zh) end
        P.treeModFin = P.treeModFin or {}   -- 结算页（t.last）写这一局研究完了哪几项
        P.treeModFin[key] = P.treeModFin[key] or {}
        table.insert(P.treeModFin[key], m.cur)
        m.cur, m.rp = nil, 0
      end
    end
    return math.floor(used)
  end
  G.treeAddModRp = addModRp
  G.ACT.treeMod = function(P, key, mk)
    local t = T(P)
    local it = type(key) == "string" and TT.byKey[key]
    if not t or not it or type(mk) ~= "string" or not TT.owned(t, key) then return end
    local m = modsOf(t, key)
    if not WM.canResearch(it, m.done, mk) then G.msg(P.pl, "bad", "tree.modLocked") return end
    if m.cur ~= mk then m.cur, m.rp = mk, 0 end
    publish(P)
    save(P)
  end
  -- 乘员：这辆车在阵容第几位，用那一位的乘员
  local function crewOf(t, nat, slot)
    t.crew = t.crew or {}
    t.crew[nat] = t.crew[nat] or {}
    local k = tostring(slot)
    local c = t.crew[nat][k]
    if not c then
      c = { xp = 0, sk = {} }
      t.crew[nat][k] = c
    end
    return c
  end
  local function slotOf(t, it)
    local L = t.lineup[it.nat] or {}
    return table.find(L, it.key)
  end
  G.treeCrewOf = function(P, key)
    local t = T(P)
    local it = TT.byKey[key]
    local slot = t and it and slotOf(t, it)
    return slot and crewOf(t, it.nat, slot) or nil
  end
  G.ACT.crewUp = function(P, nat, slot, skill)
    local t = T(P)
    slot = tonumber(slot)
    if not t or not TT.NAT[nat] or not slot or slot < 1 or slot > LINEUP or type(skill) ~= "string" then return end
    local ok = false
    for _, s in ipairs(WC.SKILLS) do if s.key == skill then ok = true end end
    if not ok then return end
    local c = crewOf(t, nat, math.floor(slot))
    local lv = c.sk[skill] or 0
    if lv >= WC.MAXLV then return end
    if WC.free(c) < WC.stepCost(lv + 1) then G.msg(P.pl, "bad", "tree.crewNoPts") return end
    c.sk[skill] = lv + 1
    publish(P)
    save(P)
  end

  -- 这辆车装了的改装合起来的效果（出车时写到车上）
  function G.treeFx(P, key)
    local t = T(P)
    local it = TT.byKey[key]
    if not t or not it then return nil end
    return WM.fx(it, (t.mods and t.mods[key] and t.mods[key].done) or {})
  end

  -- 选研究目标：能研究的才行；这个系攒着的 free 先灌进去
  G.ACT.treeResearch = function(P, key)
    local t = T(P)
    local it = type(key) == "string" and TT.byKey[key]
    if not t or not it then return end
    local ok, why = TT.canResearch(t, key)
    if not ok then
      G.msg(P.pl, "bad", "tree.cant." .. tostring(why))
      return
    end
    t.cur[it.nat .. ":" .. it.branch] = key
    local f = t.free[it.nat] or 0
    if f > 0 then
      t.free[it.nat] = nil
      addRp(P, key, f)
    end
    publish(P)
    save(P)
  end
  -- 买：研究完了才能买；无限金币（Config.Economy.infinite）照样不扣
  G.ACT.treeBuy = function(P, key)
    local t = T(P)
    local it = type(key) == "string" and TT.byKey[key]
    if not t or not it or TT.owned(t, key) then return end
    if not TT.researched(t, key) then G.msg(P.pl, "bad", "tree.needRes") return end
    local E = Config.Economy or {}
    if not E.infinite then
      local d = P.data
      if (d.coins or 0) < it.cost then G.msg(P.pl, "bad", "eco.poor", it.cost - (d.coins or 0)) return end
      if G.addCoins then G.addCoins(P, -it.cost) else d.coins -= it.cost end
    end
    t.own[key] = true
    -- 阵容没满：顺手放进去（战雷里买了车也是顺手放进空的乘员组）
    local L = t.lineup[it.nat] or defaultLineup(t, it.nat)
    local inL = false
    for _, k in ipairs(L) do if k == key then inL = true end end
    if not inL and #L < LINEUP then table.insert(L, key) end
    G.msg(P.pl, "good", "tree.bought", it.name, it.cost)
    publish(P)
    save(P)
  end
  -- 出击阵容：一个系最多 LINEUP 辆，买下的才行
  G.ACT.treeLineup = function(P, nat, keys)
    local t = T(P)
    if not t or not TT.NAT[nat] or type(keys) ~= "table" then return end
    local out, seen = {}, {}
    for _, k in ipairs(keys) do
      local it = type(k) == "string" and TT.byKey[k]
      if it and it.nat == nat and TT.owned(t, k) and not seen[k] and #out < LINEUP then
        seen[k] = true
        table.insert(out, k)
      end
    end
    t.lineup[nat] = out
    publish(P)
    save(P)
  end
  G.ACT.treeNat = function(P, nat)
    local t = T(P)
    if not t or not TT.NAT[nat] then return end
    t.nat = nat
    if not t.lineup[nat] then defaultLineup(t, nat) end
    publish(P)
    save(P)
  end
  -- 现在的阵容（没有就给默认的）
  function G.treeLineup(P)
    local t = T(P)
    if not t then return {} end
    return t.lineup[t.nat] or defaultLineup(t, t.nat)
  end

  -- 一局结束发研究点：按这一局的得分（击毁、占点都在里面），赢了多三成；分给这一局用过的树正在研究的那辆，没选的进 free
  function G.treeAward(P, won)
    local t = T(P)
    if not t then return 0 end
    local base = math.floor((P.score or 0) * 8 + (P.kills or 0) * 250 + 300)
    local mk = ((W.modeK or {})[G.wtModeNow and G.wtModeNow() or "rb"]) or 1   -- 历史 ×1.3、全真 ×1.6（战雷：越真实奖励越多）
    local rp = math.floor(base * (won and 1.3 or 1) * mk)
    P.treeModeK = mk
    local used = P.treeUsed or {}
    local brs = {}
    for _, br in ipairs(TT.BRANCHES) do if used[br] then table.insert(brs, br) end end
    if #brs == 0 then brs = { "ground" } end
    local each = math.floor(rp / #brs)
    for _, br in ipairs(brs) do
      local key = t.cur[t.nat .. ":" .. br]
      if key then addRp(P, key, each) else t.free[t.nat] = (t.free[t.nat] or 0) + each end
    end
    -- 改装：这一局开过的每辆车平分（战雷：车自己的改装和下一辆车的研究同时拿研究点）
    local keys = {}
    for k in pairs(P.treeUsedKeys or {}) do table.insert(keys, k) end
    P.treeModGain = {}
    if #keys > 0 then
      local per = math.floor(rp / #keys)
      for _, k in ipairs(keys) do P.treeModGain[k] = addModRp(P, k, per) end
    end
    -- 乘员：开过的车所在的那一位攒经验（每位只算一次）
    P.treeCrewGain = {}
    local cxp = math.floor(WC.award(P.score, P.kills, won) * mk)
    local seen = {}
    for _, k in ipairs(keys) do
      local it = TT.byKey[k]
      local slot = it and slotOf(t, it)
      if slot and not seen[it.nat .. slot] then
        seen[it.nat .. slot] = true
        local c = crewOf(t, it.nat, slot)
        local lv0 = WC.level(c.xp)
        c.xp += cxp
        P.treeCrewGain[k] = cxp
        if WC.level(c.xp) > lv0 and P.pl then G.msg(P.pl, "good", "tree.crewLv", slot, WC.level(c.xp)) end
      end
    end
    -- 结算页的明细（客户端 TechUI G.treeResultText，WtBattle 结算页那一行）：研究点、倍率、记在哪辆上、改装、乘员经验
    local last = { n = (G.round and G.round.n) or 0, rp = rp, mk = mk, won = won == true, cur = {}, mods = {}, crew = {} }
    for _, br in ipairs(brs) do
      local ck = t.cur[t.nat .. ":" .. br]
      local cit = ck and TT.byKey[ck]
      if cit then table.insert(last.cur, { k = ck, rp = t.rp[ck] or 0, need = cit.rp }) end
    end
    for k, g in pairs(P.treeModGain or {}) do last.mods[k] = { g = g, fin = (P.treeModFin or {})[k] or {} } end
    for k, x in pairs(P.treeCrewGain or {}) do last.crew[k] = x end
    t.last = last
    P.treeModFin = {}
    P.treeUsed, P.treeUsedKeys = {}, {}
    if rp > 0 and P.pl then G.msg(P.pl, "good", "tree.rp", rp) end
    publish(P)
    return rp
  end

  ---------------------------------------------------------------- 战斗等级配对（用户 11-25「都要做」：按战斗等级配对）

  -- 这一局的战斗等级：准备阶段在线真人出击阵容里最高的那辆（战雷一场仗按最高的配对）；开战以后定住（中途进来的人不改）；没人按 W.br0
  --   写给客户端：workspace 属性 WtBr（机库显示「本局战斗等级」、超出的车标灰）
  --   准备阶段（和开战前）一直按在线的人重算；开战以后第一次有真人阵容时锁住——服务器上一个真人都没有时不锁，
  --   免得第一个进来的人被开局那一下的默认值卡住
  local roundBr, lockN = nil, -1
  function G.treeRoundBr()
    local R = G.round
    local n = R and R.n or 0
    if roundBr and lockN == n then return roundBr end
    local best = 0
    for _, P in pairs(G.P) do
      if P.pl and P.data then
        local br = TT.lineupBr(G.treeLineup(P))
        if br > best then best = br end
      end
    end
    local v = (best > 0) and best or (W.br0 or 4.0)
    if v ~= roundBr then pcall(function() workspace:SetAttribute("WtBr", v) end) end
    roundBr = v
    if R and R.phase == "battle" and best > 0 then lockN = n end
    return v
  end
  -- 三种模式（街机 ab / 历史 rb / 全真 sb）：准备阶段按在线的人投的票（票一样多按 W.mode0），开战以后定住；写给客户端 workspace 属性 WtMode
  local MODES = { ab = true, rb = true, sb = true }
  local modeNow, modeLock = nil, -1
  function G.wtModeNow()
    local R = G.round
    local n = R and R.n or 0
    if modeNow and modeLock == n then return modeNow end
    local cnt, real = { ab = 0, rb = 0, sb = 0 }, 0
    for _, P in pairs(G.P) do
      if P.pl then
        real += 1
        if MODES[P.modeVote] then cnt[P.modeVote] += 1 end
      end
    end
    local best, bn = W.mode0 or "rb", 0
    for _, m in ipairs({ "ab", "rb", "sb" }) do
      if cnt[m] > bn then best, bn = m, cnt[m] end
    end
    if best ~= modeNow then pcall(function() workspace:SetAttribute("WtMode", best) end) end
    modeNow = best
    if R and R.phase == "battle" and real > 0 then modeLock = n end
    return best
  end
  G.ACT.wtModeVote = function(P, m)
    if not MODES[m] then return end
    P.modeVote = m
    pcall(function() P.pl:SetAttribute("ModeVote", m) end)
    G.wtModeNow()
  end
  G.on("roundStart", function() modeNow, modeLock = nil, -1 G.wtModeNow() end)

  -- 这一局能出的最高战斗等级（战雷：最多碰到比自己高 brUp 的）
  function G.treeBrCap() return G.treeRoundBr() + (W.brUp or 1.0) end
  G.on("roundStart", function() roundBr, lockN = nil, -1 G.treeRoundBr() end)
  task.spawn(function()   -- 准备阶段有人进出、换阵容：机库上的「本局战斗等级」跟着变
    while true do
      task.wait(2)
      pcall(G.treeRoundBr)
      pcall(G.wtModeNow)
    end
  end)

  -- 电脑开的地面车（AIVeh.lua）：从科技树里挑这一局战斗等级 [BR − brUp, BR] 的；系优先挑队里真人用的那几个，
  --   没有真人按阵营（攻方中、俄，守方美、德、日）；cat：tank / apc（AIVeh 按三成二坦克掷的）；ok(型号)：AI 开得了（坦克 / 步战车、有武器）
  local TEAM_NAT = { atk = { "cn", "ru" }, def = { "us", "de", "jp" } }
  function G.treePickAi(team, cat, ok)
    local br = G.treeRoundBr()
    local nats, seen = {}, {}
    for _, P in pairs(G.P) do
      local t = P.team == team and P.data and P.data.tree
      if t and t.nat and not seen[t.nat] then seen[t.nat] = true table.insert(nats, t.nat) end
    end
    if #nats == 0 then nats = TEAM_NAT[team] or TEAM_NAT.atk end
    for _, span in ipairs({ W.brUp or 1.0, 2.0, 99 }) do   -- 窗口里没有就放宽
      local cand = {}
      for _, nat in ipairs(nats) do
        for _, it in ipairs(TT.list[nat].ground) do
          local d = VD.get(it.play)
          if d and d.cat == cat and (not ok or ok(it.play)) and it.br <= br + 0.05 and it.br >= br - span - 0.05 then table.insert(cand, it) end
        end
      end
      if #cand > 0 then return cand[math.random(#cand)] end
    end
    return nil
  end

  ---------------------------------------------------------------- 出击：直接坐进车里 / 飞机里

  -- 本队这一类（地面 / 空中）的召唤位：在自己基地里、开着的、空着的先
  local function padFor(team, air)
    local best, free
    for _, p in ipairs(G.pads or {}) do
      local okKind = air and (p.kind == "air" and not p.heli) or (not air and p.kind == "veh")
      if okKind and p.team == team and (not G.padOpen or G.padOpen(p, team)) then
        local busy = G.padBusy and G.padBusy(p)   -- 上面停着刚出来的车（电脑车也从这里出）：先挑空着的
        if not busy and p.summon then return p end
        if not busy then free = free or p end
        best = best or p
      end
    end
    return free or best
  end
  G.treePadFor = padFor

  -- 「下车」= 回机库（战雷：离开载具就是这辆没了）：车留下变残骸，人阵亡回出击界面；PvE、测试里的步兵（G.allowInfantry）照旧能下车
  function G.treeLeave(P)
    if not (W.noInfantry and not G.allowInfantry) then return false end
    local e = P.vehicle
    if not e or not e.alive or e.driver ~= P then return false end
    local hum = P.char and P.char:FindFirstChildOfClass("Humanoid")
    -- 直接判毁（G.wtRaw：不走战雷的乘员 / 模块伤害，Ents.damageEnt 照老办法扣血；车被毁，里面的人跟着阵亡）
    G.wtRaw = true
    pcall(G.damageEnt, e, (e.hp or 0) + 1e6, nil)
    G.wtRaw = nil
    if hum and hum.Health > 0 then hum.Health = 0 end
    return true
  end

  -- 改装（WtMods）、乘员（WtCrew）的效果写到车上——机动、炮塔按倍率（客户端 Drive / Fly 乘）；零件、灭火器、工具箱给 Wt.lua 查；
  --   烟幕弹、热焰弹没研究就没有；弹种只认前 ModAmmo 种；飞机血量按倍率；装填、乘员血量按乘员技能
  local function applyFx(e, air, fx, cf)
    if not fx then return end
    cf = cf or WC.fx({})
    fx.repK *= cf.repK
    e.wtFx = fx
    local m = e.model
    if air then
      m:SetAttribute("ModThr", fx.thr)
      if fx.hp ~= 1 and e.hp then
        e.maxHp = math.floor((e.maxHp or e.hp) * fx.hp)
        e.hp = math.floor(e.hp * fx.hp)
        m:SetAttribute("MaxHp", e.maxHp)
        m:SetAttribute("Hp", e.hp)
      end
      if not fx.flares and e.flares then
        e.flares = 0
        m:SetAttribute("Flares", 0)
      end
    else
      m:SetAttribute("ModSpd", fx.speed)
      m:SetAttribute("ModAcc", fx.accel * cf.drive)
      m:SetAttribute("ModTurn", fx.turn * cf.drive)
      m:SetAttribute("ModTrav", fx.trav * cf.trav)
      m:SetAttribute("ModAmmo", fx.ammo)
      m:SetAttribute("CrewRel", cf.rel)   -- 装填（服务器 Armor.lua、客户端 Drive.lua 都乘）
      e.crewRel = cf.rel
      if not fx.smoke then e.smokeLeft = 0 end
      if e.wt and cf.vital ~= 1 then   -- 耐力：车里每个乘员的血（Wt.lua）
        for _, c in ipairs(e.wt.crew or {}) do
          c.max = c.max * cf.vital
          c.hp = c.max
        end
        if G.wtPush then G.wtPush(e) end
      end
    end
  end

  ---------------------------------------------------------------- 试驾（用户 11-25「都要做」）：机库 / 科技树里点「试驾」——
  --   人和车放到地图东边远离战场的一块平地（每人一块），车头前 300 / 600 / 1000 米摆三辆不动的靶车（打掉 10 秒后再摆一辆）；
  --   科技树里随便哪一辆都能试（没研究、没买的也行），改装全装上；不花 SP、不进阵容、不给分、阵亡不扣兵力；下车回机库
  local tests = {}   -- [P] = { veh, dummies, base, dir }
  local DUMMY = { "t90m", "m1a2", "ztz96", "m1a1" }
  local function flatOk(x, z)
    local Map = G.Map
    return Map.height(x, z) > 2 and (not Map.slope or Map.slope(x, z) < 0.3)
  end
  local function testSpot(P)
    local Map = G.Map
    local half = (Map.HALF or Map.SIZE or 38000)
    local i = 0
    for _ in pairs(tests) do i += 1 end
    local x0 = math.min(30000, half * 0.78)
    local dir = Vector3.new(-1, 0, 0)   -- 朝西（地图中间）打靶
    for k = 0, 30 do   -- 一块块往外找，靶车的位置都平
      local x, z = x0 - (k % 6) * 900, (i - 2) * 3600 + math.floor(k / 6) * 900
      local ok = flatOk(x, z)
      for _, m in ipairs({ 300, 600, 1000 }) do
        if ok and not flatOk(x + dir.X * m * 2.8, z + dir.Z * m * 2.8) then ok = false end
      end
      if ok then return Vector3.new(x, Map.height(x, z), z), dir end
    end
    return Vector3.new(x0, Map.height(x0, 0), 0), dir
  end
  local function testClean(P)
    local s = tests[P]
    if not s then return end
    tests[P] = nil
    P.inTest = nil
    for _, d in ipairs(s.dummies) do if d.alive then pcall(G.removeEnt, d) end end
    if s.veh and s.veh.alive and s.veh.driver ~= P then pcall(G.removeEnt, s.veh) end
  end
  G.testClean = testClean
  local function dummyAt(s, i)
    local m = ({ 300, 600, 1000 })[i]
    local pos = s.base + s.dir * m * 2.8 + Vector3.new(((i % 2) == 0 and 1 or -1) * 30, 0, 0)
    local id = DUMMY[((i - 1) % #DUMMY) + 1]
    if not VD.get(id) then id = "m1a1" end   -- 11-25 C：M10 删了（用户 11-24），兜底换 M1A1
    local ok, d = pcall(G.spawnGroundVeh, s.foe, id, CFrame.lookAt(pos, pos - s.dir), false, nil, nil)   -- 对面那一队（界面按队伍上色）；不给分、不记击毁
    if not ok or not d then return end
    d.noScore, d.testDummy = true, true   -- 不给分、不记击毁（Ents.lua / WtMatch.lua 跳过）
    d.model:SetAttribute("Driver", -1)
    d.model:SetAttribute("TestDummy", true)
    s.dummies[i] = d
    local onDeath = d.onDeath
    d.onDeath = function(self, src)
      if onDeath then onDeath(self, src) end
      task.delay(10, function() if tests[s.P] == s then dummyAt(s, i) end end)   -- 打掉 10 秒后再摆一辆
    end
  end
  G.ACT.testDrive = function(P, key)
    local it = type(key) == "string" and TT.byKey[key]
    if not it or P.alive or G.pve or not G.ACT.deploy then return end
    if now() < (P.canDeployAt or 0) then G.msg(P.pl, "info", "tree.waitDeploy", math.ceil((P.canDeployAt or 0) - now())) return end
    local air = it.branch == "air"
    local function go()
      if not P.alive or not P.char then return end
      testClean(P)
      local base, dir = testSpot(P)
      local s = { P = P, base = base, dir = dir, dummies = {}, foe = (P.team == "atk") and "def" or "atk" }
      tests[P] = s
      P.inTest = true
      local e
      if air then
        local pos = base + Vector3.new(0, W.airSpawnH or 1200, 0)
        local d = AD.get(it.play)
        e = G.spawnAircraftAir and G.spawnAircraftAir(P.team, it.play, CFrame.lookAt(pos, pos + dir), nil, P, nil, ((d and d.vMil) or 200) * 0.8)
      else
        e = G.spawnGroundVeh(P.team, it.play, CFrame.lookAt(base, base + dir), false, P, nil)
      end
      if not e then testClean(P) return end
      s.veh = e
      e.testDrive, e.noScore, e.treeKey = true, true, key
      e.model:SetAttribute("TreeKey", key)
      e.model:SetAttribute("TestDrive", true)
      local all = {}
      for _, m in ipairs(WM.list(it)) do all[m.key] = true end
      applyFx(e, air, WM.fx(it, all), nil)   -- 试驾：改装全装上
      for i = 1, 3 do dummyAt(s, i) end
      P.char:PivotTo(e.root.CFrame * CFrame.new(0, 2, 0))
      if G.ACT.enterVeh then G.ACT.enterVeh(P, e.id) end
      G.msg(P.pl, "info", "tree.testOn", it.name)
    end
    G.ACT.deploy(P, "crew", air and "baseAir" or "base", go)
  end
  -- 试驾下车 / 在试驾场被打掉：回机库不算阵亡，不用等重生倒计时（战雷：试驾完马上能再试驾、能出击）——
  --   Round 在阵亡时记的 canDeployAt 晚一帧清掉（同一帧里 Round 的阵亡处理可能排在后面）
  G.on("died", function(P)
    if not tests[P] then return end
    task.defer(function()
      testClean(P)
      P.canDeployAt = math.min(P.canDeployAt or 0, now())
    end)
  end)
  G.on("left", function(P) testClean(P) end)

  -- 出击：key 是阵容里的一辆；人还没出生就先按出击把人生出来，生出来以后（Round.lua 的 P.after）摆车、坐进去
  G.ACT.deployVeh = function(P, key)
    local t = T(P)
    local it = type(key) == "string" and TT.byKey[key]
    if not t or not it then return end
    if not TT.owned(t, key) then G.msg(P.pl, "bad", "tree.notOwned") return end
    local inL = false
    for _, k in ipairs(G.treeLineup(P)) do if k == key then inL = true end end
    if not inL then G.msg(P.pl, "bad", "tree.notInLineup") return end
    local air = it.branch == "air"
    -- 战斗等级：这一局最高能出 BR + brUp（战雷：最多碰到比自己高 1.0 的）
    if not G.pve and it.br > G.treeBrCap() + 0.05 then
      G.msg(P.pl, "bad", "tree.brHigh", TT.brText(it.br), TT.brText(G.treeRoundBr()), TT.brText(G.treeBrCap()))
      return
    end
    local p = padFor(P.team, air)
    if not p then G.msg(P.pl, "bad", "ui.padLocked") return end
    local vid = it.play
    local kind = air and "air" or "veh"
    P.wtKey = key   -- WtMatch 按科技树的键记阵容（借同一型号的两辆算两种）
    local okSp = not G.wtSpawnOk or G.wtSpawnOk(P, vid, kind)
    P.wtKey = nil
    if not okSp then return end
    local function go()
      if not P.alive or not P.char or P.vehicle then return end
      -- 人挪到召唤台边上（召唤台按「人在终端旁边」查），再按召唤台生成、坐进去
      local hrp = P.char:FindFirstChild("HumanoidRootPart")
      if hrp then P.char:PivotTo(CFrame.new(p.term + Vector3.new(0, 3, 0))) end
      P.padT = 0
      P.treeSpawn, P.wtKey = true, key
      local okS, e
      if air and G.wtModeNow and G.wtModeNow() == "ab" and G.spawnAircraftAir then
        -- 街机：飞机直接在空中出生——本队机场上空 airSpawnH 格，机头朝据点那一片的中间，按军推速度的八成飞
        okS, e = pcall(function()
          local c = p.base.Position
          local mx, mz, n = 0, 0, 0
          for _, pt in ipairs((G.Map and G.Map.POINTS) or {}) do mx += pt.x mz += pt.z n += 1 end
          local look = (n > 0) and Vector3.new(mx / n - c.X, 0, mz / n - c.Z) or Vector3.new(p.base.LookVector.X, 0, p.base.LookVector.Z)
          if look.Magnitude < 1 then look = Vector3.new(0, 0, -1) end
          local pos = Vector3.new(c.X, c.Y + (W.airSpawnH or 1200), c.Z)
          if G.wtSpawnOk and not G.wtSpawnOk(P, vid, "air") then return nil end
          local d = AD.get(vid)
          local ee = G.spawnAircraftAir(P.team, vid, CFrame.lookAt(pos, pos + look.Unit), nil, P, nil, ((d and d.vMil) or 200) * 0.8)
          if ee and G.wtSpawned then G.wtSpawned(P, vid, "air", ee) end
          return ee
        end)
      else
        okS, e = pcall(function() return G.padSpawnAt and G.padSpawnAt(P, p, nil, vid) end)
      end
      P.treeSpawn, P.wtKey = nil, nil
      if not okS then warn("[科技树] 出击出错：" .. tostring(e)) e = nil end
      if not e then return end
      e.treeKey = key
      e.model:SetAttribute("TreeKey", key)   -- 客户端名牌、击杀提示按科技树的名字写（借来的型号也写自己的名字）
      P.treeUsed = P.treeUsed or {}
      P.treeUsed[it.branch] = true
      P.treeUsedKeys = P.treeUsedKeys or {}
      P.treeUsedKeys[key] = true   -- 一局结束这辆车的改装拿研究点
      P.treeCur = key   -- 击杀栏（Round.lua creditDeath）写这一辆的名字
      local tcur = T(P)
      local slot = tcur and slotOf(tcur, it)
      applyFx(e, air, G.treeFx(P, key), WC.fx(slot and crewOf(tcur, it.nat, slot).sk or {}))
      P.char:PivotTo(e.root.CFrame * CFrame.new(0, 2, 0))
      if G.ACT.enterVeh then G.ACT.enterVeh(P, e.id) end
      if P.vehicle ~= e then   -- 没坐上（召唤位上有东西挡着之类）：车留着，人在旁边
        G.msg(P.pl, "info", "tree.walkIn")
      end
    end
    if P.alive and P.char then
      go()
    elseif G.ACT.deploy then
      -- 刚阵亡（车没了）：复活倒计时没到——告诉玩家还要几秒，到点自动出这一辆（原来点了没反应）
      local wait = (P.canDeployAt or 0) - os.clock()
      if wait > 0.05 then
        G.msg(P.pl, "info", "tree.waitDeploy", math.ceil(wait))
        P.treeQueued = key
        task.delay(wait + 0.05, function()
          if P.treeQueued == key and not P.alive and G.P[P.pl] == P then
            P.treeQueued = nil
            G.ACT.deployVeh(P, key)
          end
        end)
        return
      end
      P.treeQueued = nil
      G.ACT.deploy(P, "crew", air and "baseAir" or "base", go)
    end
  end
end

return Tech
