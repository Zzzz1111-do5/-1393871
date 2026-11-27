-- 全面大战场（服务器）——科技树：研究、购买、出击阵容、出击（用户 11-25：「从1960到现代的战机和坦克 科技树」「再去做一个中 德 美 日 俄系」
--   「不要让玩家拿枪之类的了 就跟战雷完全一样 不要让玩家作为个体活动」）
--   存档 P.data.tree：res 研究完的、own 买下的、rp[key] 攒着的研究点、cur[系:树] 正在研究的、lineup[系] 出击阵容（最多 5 辆）、nat 现在用哪个系、
--     free[系] 没处放的研究点（研究完多出来的、没选研究目标时挣的）；P.data.codes[码的编号] 兑换过的码（不写给客户端）
--   白送的只有每系每棵树一辆起步车（TechTree TT.starter，用户 11-26「每个系从只给一辆最基础的坦克开始」），别的研究完再拿金币买
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
  -- 用户 11-25「5 个槽位限制只能带两个飞行单位」「最多两个飞行单位」：阵容里飞机 + 直升机加起来最多 AIR_MAX 个
  local AIR_MAX = W.lineupAir or 2
  local function isAir(k) local it = TT.byKey[k] return it ~= nil and (it.branch == "air" or it.branch == "heli") end
  local function airIn(L) local n = 0 for _, k in ipairs(L) do if isAir(k) then n += 1 end end return n end
  G.treeAirMax = AIR_MAX

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
  -- 第一次玩（阵容空着）：白送的起步车放进阵容（每棵树一辆：坦克、飞机、直升机；TechTree TT.starter）；
  --   留一个空位：第一辆买下的车自动放进去（不然直升机树也白送一架以后阵容一开始就满了）。按树、按树里的顺序排（坦克在前）
  local function defaultLineup(t, nat)
    local pick, n, cap, na = {}, 0, LINEUP - 1, 0
    for pass = 1, 2 do
      for bi, br in ipairs(TT.BRANCHES) do
        for i, it in ipairs(TT.list[nat][br]) do
          local air = br == "air" or br == "heli"
          if it.free and not pick[it.key] and n < cap and not (air and na >= AIR_MAX) then
            if air then na += 1 end
            pick[it.key], n = bi * 1000 + i, n + 1
            if pass == 1 then break end
          end
        end
      end
    end
    local out = {}
    for k in pairs(pick) do table.insert(out, k) end
    table.sort(out, function(a, b) return pick[a] < pick[b] end)
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

  ---------------------------------------------------------------- 兑换码（用户 11-25「设置一个兑换码 在设置里」「兑换码 Zhengyongshuo 直接解锁所有载具」）
  --   码只放在服务器脚本里（客户端看不到）；存档里记的是编号 id（P.data.codes[id] = 兑换的时间，不进写给客户端的 Tree 属性）；
  --   all：科技树每一辆都记成研究完 + 买下——读档时也补一遍，以后加的新车兑过的人自动有（用户 11-26：兑换的结果要存进档）
  local CODES = { zhengyongshuo = { id = "all", all = true } }
  local CODE_BY_ID = {}
  for _, R in pairs(CODES) do CODE_BY_ID[R.id] = R end
  -- 「全部解锁」：返回这次新解锁了几辆
  local function unlockAll(t)
    local n = 0
    for key in pairs(TT.byKey) do
      if not (t.res[key] == true and t.own[key] == true) then n += 1 end
      t.res[key] = true
      t.own[key] = true
    end
    return n
  end
  local function unlockByCodes(t, codes)
    for id in pairs(codes or {}) do
      local R = CODE_BY_ID[id]
      if R and R.all then unlockAll(t) end
    end
  end

  -- 读档（用户 11-26「账号的载具解锁要能保留」）：研究完 / 买下的照收——科技树暂时删掉的车（认不得的 key）也原样留着，
  --   以后加回来还算；兑换过的码补一遍；阵容、乘员按下面「阵容」那段整理
  local ef = G.econFromSave
  G.econFromSave = function(P, d)
    if ef then ef(P, d) end
    local src = (type(d) == "table" and type(d.tree) == "table") and d.tree or {}
    local t = blank()
    t.nat = TT.NAT[src.nat] and src.nat or "cn"
    for _, f in ipairs({ "res", "own" }) do
      local n = 0
      for k, v in pairs(type(src[f]) == "table" and src[f] or {}) do
        if type(k) == "string" and #k <= 40 and v == true and n < 500 then
          t[f][k] = true
          n += 1
        end
      end
    end
    local codes = {}
    for id, v in pairs(type(d) == "table" and type(d.codes) == "table" and d.codes or {}) do
      if type(id) == "string" and #id <= 32 and (v == true or type(v) == "number") then codes[id] = v end
    end
    P.data.codes = codes
    unlockByCodes(t, codes)
    for k, v in pairs(type(src.rp) == "table" and src.rp or {}) do
      if TT.byKey[k] and type(v) == "number" and v > 0 then t.rp[k] = math.floor(v) end
    end
    for k, v in pairs(type(src.cur) == "table" and src.cur or {}) do
      if type(k) == "string" and TT.byKey[v] then t.cur[k] = v end
    end
    -- 乘员：先按原来的位置读出来（只留认得的技能、级数在范围里；点数超了（改过规则）就清零重点），阵容挪了位置乘员跟着车走
    local crewOld = {}
    for _, nat in ipairs(TT.NATIONS) do
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
          out[i] = o
        end
      end
      crewOld[nat] = out
    end
    -- 阵容：认得的、这个系的、买下的才留（飞行单位最多 AIR_MAX 个）；11-26 以前白送、档里没记的车（每棵树第一级各列打头的都白送过：
    --   M551、BMP-1、T-72 乌拉尔……）现在不算买下了——在阵容里的换成这棵树的起步车（只换一次，起步车已经在阵容里就去掉）；
    --   阵容里一辆地面车都没有（第一辆必须是地面车，出不了击）就补上起步坦克；全空了按默认阵容
    for _, nat in ipairs(TT.NATIONS) do
      local f = type(src.free) == "table" and tonumber(src.free[nat]) or nil
      if f and f > 0 then t.free[nat] = math.floor(f) end
      local L = type(src.lineup) == "table" and src.lineup[nat]
      local map = nil   -- 新位置 → 原来的位置（乘员跟着车）
      if type(L) == "table" then
        local out, seen, swapped = {}, {}, {}
        map = {}
        for _, k in ipairs(L) do
          local it = type(k) == "string" and TT.byKey[k]
          if it and it.nat == nat then seen[k] = true end
        end
        for i, k in ipairs(L) do
          local it = type(k) == "string" and TT.byKey[k] or nil
          if it and it.nat == nat and not TT.owned(t, k) and not swapped[it.branch] then
            local st = TT.starter(nat, it.branch)
            if st and not seen[st.key] then
              it, k = st, st.key
              seen[k] = true
            end
            swapped[it.branch] = true
          end
          if it and it.nat == nat and TT.owned(t, k) and not table.find(out, k) and #out < LINEUP and not (isAir(k) and airIn(out) >= AIR_MAX) then
            table.insert(out, k)
            map[#out] = i
          end
        end
        local st = TT.starter(nat, "ground")
        local hasGround = false
        for _, k in ipairs(out) do if TT.byKey[k].branch == "ground" then hasGround = true end end
        if #out > 0 and st and not hasGround then
          if #out >= LINEUP then
            map[#out] = nil
            table.remove(out)
          end
          table.insert(out, st.key)
        end
        t.lineup[nat] = #out > 0 and out or nil   -- 阵容里的车都删了（11-25 没有原模型的删掉）：按默认阵容重新排
        if #out == 0 then map = nil end
      end
      -- 乘员挪到车的新位置；跟着的车去掉了的放到空着的位置上（不丢经验、技能）
      local outC, used, frees = {}, {}, {}
      if map then
        for ni, oi in pairs(map) do
          if crewOld[nat][oi] then
            outC[tostring(ni)] = crewOld[nat][oi]
            used[oi] = true
          end
        end
      end
      for i = 1, LINEUP do if not outC[tostring(i)] and not (map and map[i] ~= nil) then table.insert(frees, i) end end
      for oi = 1, LINEUP do
        local c = crewOld[nat][oi]
        if c and not used[oi] then
          local slot = map and table.remove(frees, 1) or oi
          if slot then outC[tostring(slot)] = c end
        end
      end
      t.crew[nat] = outC
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
    P.data.tree = t
    publish(P)
  end
  -- 存档合并了别的服务器写的解锁（Store.lua writeOnce）：兑换过的码再补一遍，写给客户端
  G.treeReload = function(P)
    local t = T(P)
    if not t then return end
    unlockByCodes(t, P.data.codes)
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
  -- 买：研究完了才能买，金币够才买得起（扣金币；用户 11-26「金币不要设置成无限」，Config.Economy.infinite 关着）
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
    if not inL and #L < LINEUP and not (isAir(key) and airIn(L) >= AIR_MAX) then table.insert(L, key) end   -- 飞行单位满两个了不顺手放
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
        if isAir(k) and airIn(out) >= AIR_MAX then
          G.msg(P.pl, "bad", "tree.airMax", AIR_MAX)
        else
          seen[k] = true
          table.insert(out, k)
        end
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
  ---------------------------------------------------------------- 兑换码（码的表在上面 CODES）：不分大小写、去掉首尾空格；
  --   兑了就把科技树每一辆都记成研究完 + 买下，码的编号记进 P.data.codes（读档时再补一遍：以后加的新车也有）；
  --   结果写在玩家属性 Redeem（「状态|数目|序号」）给设置界面显示，另外弹一条提示；试得太快（2 秒内）不理
  local redeemAt, redeemN = {}, 0
  G.ACT.redeem = function(P, code)
    if type(code) ~= "string" or #code > 64 or not P.pl then return end
    local t = T(P)
    local tNow = now()
    local function reply(st, n)
      redeemN += 1
      pcall(function() P.pl:SetAttribute("Redeem", st .. "|" .. tostring(n or 0) .. "|" .. redeemN) end)
    end
    if not t then reply("wait") return end
    if (redeemAt[P] or -99) > tNow - 2 then reply("wait") return end
    redeemAt[P] = tNow
    local c = string.lower((string.gsub(string.gsub(code, "^%s+", ""), "%s+$", "")))
    local R = CODES[c]
    if not R then
      G.msg(P.pl, "bad", "redeem.bad")
      reply("bad")
      return
    end
    local n = 0
    if R.all then n = unlockAll(t) end
    P.data.codes = P.data.codes or {}
    if P.data.codes[R.id] == nil then P.data.codes[R.id] = os.time() end   -- 存进档（用户 11-26：兑换码解锁的要保留）
    if n > 0 then G.msg(P.pl, "good", "redeem.ok", n) else G.msg(P.pl, "info", "redeem.none") end
    reply(n > 0 and "ok" or "none", n)
    publish(P)
    save(P)
  end
  G.on("left", function(P) redeemAt[P] = nil end)

  -- 现在的阵容（没有或者被清空了就给默认的：客户端 TechUI lineupOf 也这么显示，免得机库上有车、出击说「不在阵容里」）
  function G.treeLineup(P)
    local t = T(P)
    if not t then return {} end
    local L = t.lineup[t.nat]
    if not L or #L == 0 then L = defaultLineup(t, t.nat) end
    return L
  end

  -- 这一局按得分算的研究点（击毁、占点都在得分里），赢了多三成、按模式乘；Economy.lua 结算金币也按它（金币 = 研究点 × treeK）
  local function roundRp(P, won)
    local base = math.floor((P.score or 0) * 8 + (P.kills or 0) * 250 + 300 + (P.wtKillRp or 0) / (((W.modeK or {})[G.wtModeNow and G.wtModeNow() or "rb"]) or 1))   -- wtKillRp：击毁加成（WtMatch.lua）
    local mk = ((W.modeK or {})[G.wtModeNow and G.wtModeNow() or "rb"]) or 1   -- 历史 ×1.3、全真 ×1.6（战雷：越真实奖励越多）
    return math.floor(base * (won and 1.3 or 1) * mk), mk
  end
  G.treeRoundRp = roundRp

  -- 一局结束发研究点：分给这一局用过的树正在研究的那辆，没选的进 free
  function G.treeAward(P, won)
    local t = T(P)
    if not t then return 0 end
    local rp, mk = roundRp(P, won)
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
    local last = { n = (G.round and G.round.n) or 0, rp = rp, mk = mk, won = won == true, cur = {}, mods = {}, crew = {}, coins = P.roundCoins }   -- coins：Economy.lua 刚发的金币
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
    P.roundCoins = nil
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
    -- 用户 11-26「两边的人机的车辆要符合我匹配时带的最高权重的载具」：匹配中按排着的人、开打以后按匹配进来 / 加入了的人（P.match）的阵容算，
    --   没有这样的人才看在线的所有人
    local best, anyIn = 0, false
    for _, P in pairs(G.P) do
      if P.pl and P.data and (P.queued or (R and P.match == n)) then
        anyIn = true
        local br = TT.lineupBr(G.treeLineup(P))
        if br > best then best = br end
      end
    end
    if not anyIn then
      for _, P in pairs(G.P) do
        if P.pl and P.data then
          local br = TT.lineupBr(G.treeLineup(P))
          if br > best then best = br end
        end
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
  -- alt：另一类（这一类在窄窗口里没有车，先拿另一类窄窗口里的，不先放宽——用户 11-26「人机的车辆要符合我匹配时带的最高权重的载具」）
  function G.treePickAi(team, cat, ok, alt)
    local br = G.treeRoundBr()
    local nats, seen = {}, {}
    for _, P in pairs(G.P) do
      local t = P.team == team and P.data and P.data.tree
      if t and t.nat and not seen[t.nat] then seen[t.nat] = true table.insert(nats, t.nat) end
    end
    if #nats == 0 then nats = TEAM_NAT[team] or TEAM_NAT.atk end
    -- 先挑跟本局战斗等级差不多的（BR − 0.4 ～ BR，用户 11-26「人机的车辆要符合我匹配时带的最高权重的载具」），没有再放宽到 brUp、2、不限
    for _, span in ipairs({ 0.4, W.brUp or 1.0, 2.0, 99 }) do
      for _, c in ipairs(alt and { cat, alt } or { cat }) do
        local cand = {}
        for _, nat in ipairs(nats) do
          for _, it in ipairs(TT.list[nat].ground) do
            local d = VD.get(it.play)
            if d and d.cat == c and (not ok or ok(it.play)) and it.br <= br + 0.05 and it.br >= br - span - 0.05 then table.insert(cand, it) end
          end
        end
        if #cand > 0 then return cand[math.random(#cand)] end
      end
    end
    return nil
  end

  ---------------------------------------------------------------- 出击：直接坐进车里 / 飞机里

  -- 本队这一类（地面 / 固定翼 / 直升机）的出车位：在自己基地里、开着的、空着的先（直升机停直升机坪，用户 11-25「直升机也做一下各个国家的」）
  local function padFor(team, air, heli)
    local best, free
    for _, p in ipairs(G.pads or {}) do
      local okKind = (heli and p.kind == "air" and p.heli) or (air and not heli and p.kind == "air" and not p.heli) or (not air and p.kind == "veh")
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

  -- 「下车」= 回机库（战雷：离开载具就是这辆没了）；PvE、测试里的步兵（G.allowInfantry）照旧能下车。
  --   用户 11-25「在车上按空格也不要自动阵亡了」：只认长按 H 的「回机库」（hangar = true），别的下车请求吞掉（返回 true，不让下车）；
  --   回机库：车收走、人回机库，不放阵亡（同 Round.lua 的 redeploy）；10 秒内挨过打的照老办法判毁（打的人拿分，不能拿来躲击杀）
  function G.treeLeave(P, hangar)
    if not (W.noInfantry and not G.allowInfantry) then return false end
    local e = P.vehicle
    if not e or not e.alive or e.driver ~= P then return not hangar and e ~= nil end
    if not hangar then return true end
    if e.testDrive or not e.lastHitT or now() - e.lastHitT > 10 then
      local char = P.char
      P.char, P.alive, P.vehicle = nil, false, nil   -- 先断开：角色的 Died 不再算阵亡（Round.lua onDied 只认 P.char）
      P.canDeployAt = now()
      P.dmgLog = {}
      if e.testDrive and G.testClean then pcall(G.testClean, P) end
      pcall(G.removeEnt, e)
      if char and char.Parent then char:Destroy() end
      pcall(function() P.pl.Character = nil end)
      G.msg(P.pl, "info", "tree.backHangar")
      if G.pushOne then G.pushOne(P) end
      return true
    end
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
      m:SetAttribute("FcsGen", fx.gen)   -- 火控（WtMods.FCS）：原厂是哪一代、升级了几级——客户端 Drive.lua 开镜瞄准按它
      m:SetAttribute("ModFcs", fx.gen and fx.fcs or nil)
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

  ---------------------------------------------------------------- 试驾（用户 11-25「都要做」；又「试驾的时候 飞机就从地面机场开始 然后做几个机器人飞机 我可以去打他们
  --   不会还手 也做几个地面的 然后开坦克 和防空车的时候试驾场也多一点坦克和天上的飞机」）：
  --   · 用户 11-26 晚「把训练场单独做一张地图吧」：试驾全在训练场（自己一块区块 Zones.RANGE、自己的图 MapRange，Range.lua 建），不在战场里
  --   · 坦克、步战车、防空车：每人一条靶道（射击线上的水泥坪），车头前 300～2000 米七辆靶车（两辆横着来回开），
  --     天上三架靶机绕圈（两架固定翼、一架直升机）
  --   · 飞机：停在训练场跑道东头，自己滑跑起飞；直升机：停在直升机坪；空中靶区三架靶机绕圈、地上一排靶车
  --   靶车、靶机都是对面那一队的（界面按队伍上色），没人开、不还手（电脑车也不把它们当目标：testDummy），不给分、不记击毁；
  --     打掉 10 秒后原处再来一个；靶机借无人机断链后的自动盘旋（Air.lua loiterStep）绕圈飞
  --   科技树里随便哪一辆都能试（没研究、没买的也行），改装全装上；不花 SP、不进阵容、阵亡不扣兵力；下车回机库
  local tests = {}   -- [P] = { veh, dummies = { [i] = 实体 }, drones = { [i] = 实体 }, base, dir, foe, air }
  local DUMMY = { "t90m", "m1a2", "ztz96", "m1a1", "leo2a6", "t72b3", "bmp2", "type10" }
  local DRONE_JET = { "f16", "j10", "f15", "a10c", "j8" }
  local DRONE_HELI = { "ah64e", "z10", "mi28", "mi24" }
  -- 地面试驾的靶车：射击方向多少米、往右多少米、横着来回开的半程（米，没有就不动）
  --   训练场（11-26 晚）：每人一条靶道（960 格 ≈ 340 米宽），横着偏的、来回开的都收在自己的靶道里（最多偏 150 米）
  local RANGE = { { 300, -40 }, { 500, 60 }, { 700, -70, 70 }, { 1000, 30 }, { 1300, 60, 90 }, { 1600, -110 }, { 2000, 50 } }
  -- 靶机：绕哪儿转（射击方向多少米、往右多少米）、半径（米）、离地多高（米）、速度（米 / 秒）、直升机
  local SKY = { { 1300, -400, 900, 420, 170 }, { 1800, 500, 1300, 650, 210 }, { 900, 250, 450, 70, 32, true } }
  -- 飞机试驾的地面靶：离靶机中心多少米（往前、往右）
  local AIRGROUND = { { 0, -150 }, { 40, -50 }, { -30, 60 }, { 60, 160 }, { 500, 0 }, { 520, 120 } }
  local M = 2.8   -- 一米多少格
  local function flatOk(x, z)
    local Map = G.Map
    return Map.height(x, z) > 2 and (not Map.slope or Map.slope(x, z) < 0.3)
  end
  -- 训练场（MapRange）：第几个在试驾的人用第几条靶道
  local RangeMap = G.Map.Range or require(RS:WaitForChild("MapRange"))
  local function testIndex(P)
    local used = {}
    for q, s in pairs(tests) do if q ~= P and s.idx then used[s.idx] = true end end
    for i = 0, 63 do if not used[i] then return i end end
    return 0
  end
  local function testSpot(idx)
    return RangeMap.lane(idx % RangeMap.LANES + 1)
  end
  local function pick(list, i, get)
    for k = 0, #list - 1 do
      local id = list[((i - 1 + k) % #list) + 1]
      if get(id) then return id end
    end
    return nil
  end
  local function testClean(P)
    local s = tests[P]
    if not s then return end
    tests[P] = nil
    P.inTest = nil
    for _, d in pairs(s.dummies) do if d.alive then pcall(G.removeEnt, d) end end
    for _, d in pairs(s.drones) do if d.alive then pcall(G.removeEnt, d) end end
    if s.veh and s.veh.alive and s.veh.driver ~= P then pcall(G.removeEnt, s.veh) end
  end
  G.testClean = testClean
  local function markDummy(d)
    d.noScore, d.testDummy = true, true   -- 不给分、不记击毁（Ents.lua / WtMatch.lua 跳过）；电脑车不打它（AIVeh.lua）
    d.emptyAt = nil   -- 没人开的车 / 飞机 90 秒收走（Armor.lua、Air.lua）：靶子不收（原来三辆靶车一分半以后就没了）
    d.model:SetAttribute("Driver", -1)
    d.model:SetAttribute("TestDummy", true)
  end
  local function onDeathAgain(s, d, respawn)
    local od = d.onDeath
    d.onDeath = function(self, src)
      if od then od(self, src) end
      task.delay(10, function() if tests[s.P] == s then respawn() end end)   -- 打掉 10 秒后再来一个
    end
  end
  -- 地上的靶车：第 i 辆摆在 pos、车头朝 face；swing 有值就横着来回开
  local function dummyAt(s, i, pos, face, swing)
    local id = pick(DUMMY, i, VD.get) or "m1a1"
    local ok, d = pcall(G.spawnGroundVeh, s.foe, id, CFrame.lookAt(pos, pos + face), false, nil, nil)
    if not ok or not d then return end
    markDummy(d)
    s.dummies[i] = d
    if swing then d.testSwing = { c = pos, amp = swing * M, v = 5 * M, t0 = now(), sg = (i % 2 == 0) and 1 or -1 } end   -- 5 米 / 秒来回：从摆的地方起步（不瞬移），两辆往两边开
    onDeathAgain(s, d, function() dummyAt(s, i, pos, face, swing) end)
  end
  -- 天上的靶机：绕 c 转（半径 r 米、离地 h 米、速度 v 米 / 秒）
  local function droneAt(s, i, c, r, h, v, heli)
    local id = pick(heli and DRONE_HELI or DRONE_JET, i, AD.get)
    if not id or not G.spawnAircraftAir then return end
    local R = r * M
    local a = (i * 2.1) % (2 * math.pi)
    local p = Vector3.new(c.X + math.cos(a) * R, G.Map.height(c.X, c.Z) + h * M, c.Z + math.sin(a) * R)
    local tang = Vector3.new(-math.sin(a), 0, math.cos(a))
    local ok, e = pcall(G.spawnAircraftAir, s.foe, id, CFrame.lookAt(p, p + tang), nil, nil, nil, v * M)
    if not ok or not e then return end
    markDummy(e)
    e.emptyAt = nil   -- 没人开的飞机 90 秒收走：靶机不收
    e.fuel = 1
    e.loit = { c = Vector3.new(c.X, 0, c.Z), r = R, a = a, v = v * M, y = p.Y, T = math.huge }   -- 借无人机断链后的自动盘旋（Air.lua loiterStep）
    pcall(function()
      e.model:SetAttribute("Thr", 85)
      e.model:SetAttribute("Gear", 0)
      if heli then e.model:SetAttribute("Rpm", 100) e.model:SetAttribute("Col", 0.6) end
    end)
    s.drones[i] = e
    onDeathAgain(s, e, function() droneAt(s, i, c, r, h, v, heli) end)
  end
  -- 横着来回开的靶车、靶机加油（每 0.1 秒）
  task.spawn(function()
    while true do
      task.wait(0.1)
      local t = now()
      for _, s in pairs(tests) do
        local right = Vector3.new(-s.dir.Z, 0, s.dir.X)
        for _, d in pairs(s.dummies) do   -- 来回开的那两辆
          local W = d.alive and d.testSwing
          if W then
            -- 匀速往返（正弦那样两头慢吞吞的时间太长，看起来像停着）：开到头前 15% 那段减速到停、再倒回来；车头不掉头（靶车前进、倒车）
            local u = ((t - W.t0) * W.v / W.amp) % 4
            local k = (u < 1) and u or ((u < 3) and (2 - u) or (u - 4))
            local a = math.abs(k)
            if a > 0.85 then
              local x = (a - 0.85) / 0.15
              k = math.sign(k) * (0.85 + 0.15 * (x - 0.5 * x * x))
            end
            local p = W.c + right * (W.amp * k * W.sg)
            local ok, err = pcall(function() G.moveEnt(d, G.vehBaseAt(d.def, p.X, p.Z, right)) end)
            if not ok then G.testSwingErr = tostring(err) end
          end
        end
        for _, e in pairs(s.drones) do if e.alive then e.fuel = 1 end end
      end
    end
  end)
  G.ACT.testDrive = function(P, key)
    local it = type(key) == "string" and TT.byKey[key]
    if not it or P.alive or G.pve or not G.ACT.deploy then return end
    if now() < (P.canDeployAt or 0) then G.msg(P.pl, "info", "tree.waitDeploy", math.ceil((P.canDeployAt or 0) - now())) return end
    local air = it.branch == "air" or it.branch == "heli"
    local heli = it.branch == "heli"
    if not G.rangeReady then G.msg(P.pl, "info", "tree.rangeBusy") return end   -- 训练场还在后台建（开服头一会儿）
    local idx = testIndex(P)
    -- 出车的地方（训练场里）：车在第 idx 条靶道的射击线上、飞机在跑道东头、直升机在直升机坪
    local spawnAt, spawnDir
    if heli then spawnAt, spawnDir = RangeMap.heliPad(idx)
    elseif air then spawnAt, spawnDir = RangeMap.runwayStart(idx)
    else spawnAt, spawnDir = testSpot(idx) end
    local function go()
      if not P.alive or not P.char then return end
      testClean(P)
      local s = { P = P, idx = idx, dummies = {}, drones = {}, foe = (P.team == "atk") and "def" or "atk", air = air }
      -- 流式加载：先请服务器把训练场那一片送过去（人在战场那边出生的，十万格外的地形、零件这时还没到客户端）
      if G.streamAround then G.streamAround(P.pl, spawnAt, 8) end
      if not P.alive or not P.char then return end
      local e
      if air then
        -- 飞机、直升机：靶区在挡弹墙北面（空中靶区，MapRange.AIRTGT），朝北摆靶
        s.base, s.dir = RangeMap.airTarget(), Vector3.new(0, 0, -1)
        local d = AD.get(it.play)
        local pos = Vector3.new(spawnAt.X, G.Map.height(spawnAt.X, spawnAt.Z) + ((d and d.gearH) or 5), spawnAt.Z)
        if G.spawnAircraft then
          local okS, ee = pcall(G.spawnAircraft, P.team, it.play, CFrame.lookAt(pos, pos + spawnDir), nil, P, nil)
          if okS then e = ee end
        end
        if not e and G.spawnAircraftAir then   -- 摆不到跑道上：在靶区上空出来
          local p2 = s.base + Vector3.new(0, G.Map.height(s.base.X, s.base.Z) + (heli and 140 or (W.airSpawnH or 1200)), 0)
          e = G.spawnAircraftAir(P.team, it.play, CFrame.lookAt(p2, p2 + s.dir), nil, P, nil, heli and 0 or (((d and d.vMil) or 200) * 0.8))
        end
      else
        s.base, s.dir = spawnAt, spawnDir
        e = G.spawnGroundVeh(P.team, it.play, CFrame.lookAt(s.base, s.base + s.dir), false, P, nil)
      end
      if not e then return end
      tests[P] = s
      P.inTest = true
      s.veh = e
      e.testDrive, e.noScore, e.treeKey = true, true, key
      e.model:SetAttribute("TreeKey", key)
      e.model:SetAttribute("TestDrive", true)
      local all = {}
      for _, m in ipairs(WM.list(it)) do all[m.key] = true end
      applyFx(e, air, WM.fx(it, all), nil)   -- 试驾：改装全装上
      local right = Vector3.new(-s.dir.Z, 0, s.dir.X)
      local function at(fwd, side) return s.base + s.dir * (fwd * M) + right * (side * M) end
      if air then
        local c = s.base
        droneAt(s, 1, c, 1100, 450, 180)
        droneAt(s, 2, c, 1600, 800, 220)
        droneAt(s, 3, at(300, 200), 500, 90, 35, true)
        for i, g in ipairs(AIRGROUND) do
          local p = at(g[1], g[2])
          dummyAt(s, i, Vector3.new(p.X, G.Map.height(p.X, p.Z), p.Z), s.dir, nil)
        end
      else
        for i, r in ipairs(RANGE) do
          local p = at(r[1], r[2])
          dummyAt(s, i, Vector3.new(p.X, G.Map.height(p.X, p.Z), p.Z), -s.dir, r[3])
        end
        for i, k in ipairs(SKY) do droneAt(s, i, at(k[1], k[2]), k[3], k[4], k[5], k[6]) end
      end
      P.char:PivotTo(e.root.CFrame * CFrame.new(0, 2, 0))
      if G.ACT.enterVeh then G.ACT.enterVeh(P, e.id) end
      G.msg(P.pl, "info", air and "tree.testOnAir" or "tree.testOn", it.name)
    end
    P.testDeploy = true   -- Round.lua deploy：试驾不受出生点 / 准备阶段 / 兵力限制（用户 11-26「训练场目前没发试驾飞机了」）
    G.ACT.deploy(P, "crew", air and "baseAir" or "base", go)
    P.testDeploy = nil
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
  -- 匹配中排队前查（WtMatch.lua ACT.matchJoin）：买下了、在出击阵容里（战斗等级按排着的人定，不在这里拦）
  function G.treeCanQueue(P, key)
    local t = T(P)
    local it = type(key) == "string" and TT.byKey[key]
    if not t or not it then return false end
    if not TT.owned(t, key) then G.msg(P.pl, "bad", "tree.notOwned") return false end
    for _, k in ipairs(G.treeLineup(P)) do if k == key then return true end end
    G.msg(P.pl, "bad", "tree.notInLineup")
    return false
  end
  G.ACT.deployVeh = function(P, key)
    local R0 = G.round
    if R0 and R0.phase == "queue" and G.matchOn and G.matchOn() and not P.testDeploy then   -- 还在匹配：先排上（用户 11-26「点开战先匹配」）
      if G.ACT.matchJoin then G.ACT.matchJoin(P, key) end
      return
    end
    local t = T(P)
    local it = type(key) == "string" and TT.byKey[key]
    if not t or not it then return end
    if not TT.owned(t, key) then G.msg(P.pl, "bad", "tree.notOwned") return end
    local inL = false
    for _, k in ipairs(G.treeLineup(P)) do if k == key then inL = true end end
    if not inL then G.msg(P.pl, "bad", "tree.notInLineup") return end
    local air = it.branch == "air" or it.branch == "heli"
    local heli = it.branch == "heli"
    -- 战斗等级：这一局最高能出 BR + brUp（战雷：最多碰到比自己高 1.0 的）
    if not G.pve and it.br > G.treeBrCap() + 0.05 then
      G.msg(P.pl, "bad", "tree.brHigh", TT.brText(it.br), TT.brText(G.treeRoundBr()), TT.brText(G.treeBrCap()))
      return
    end
    local p = padFor(P.team, air, heli)
    if not p then G.msg(P.pl, "bad", "ui.padLocked") return end
    local vid = it.play
    local kind = air and "air" or "veh"
    P.wtKey = key   -- WtMatch 按科技树的键记阵容（借同一型号的两辆算两种）
    local okSp = not G.wtSpawnOk or G.wtSpawnOk(P, vid, kind)
    P.wtKey = nil
    if not okSp then return end
    if R0 and (R0.phase == "prep" or R0.phase == "battle") then P.match = R0.n end   -- 这一局真打的人（AIVeh 按每队的人数补电脑车）
    local function go()
      if not P.alive or not P.char or P.vehicle then return end
      -- 人挪到召唤台边上（召唤台按「人在终端旁边」查），再按召唤台生成、坐进去
      local hrp = P.char:FindFirstChild("HumanoidRootPart")
      if hrp then P.char:PivotTo(CFrame.new(p.term + Vector3.new(0, 3, 0))) end
      P.padT = 0
      P.treeSpawn, P.wtKey = true, key
      local okS, e
      -- 飞机（用户 11-25「召唤飞机就从机场跑道开始 然后自己起飞 包括回跑道降落补给也做出来」）：不再空中出生（原来街机在机场上空、
      --   历史 / 全真退后 1500 格再高一半，C 11-25 ⑫）——停在自己机场的跑道上（Depots.lua runwayPads：顺着跑道、机头朝起飞方向），
      --   起落架放着、发动机慢车，自己推油门滑跑起飞；落回自己的跑道停稳就加油、补弹、维修（Air.lua 落地补给）
      okS, e = pcall(function() return G.padSpawnAt and G.padSpawnAt(P, p, nil, vid) end)
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
