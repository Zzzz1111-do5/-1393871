-- 全面大战场（服务器）——科技树：研究、购买、出击阵容、出击（用户 11-25：「从1960到现代的战机和坦克 科技树」「再去做一个中 德 美 日 俄系」
--   「不要让玩家拿枪之类的了 就跟战雷完全一样 不要让玩家作为个体活动」）
--   存档 P.data.tree：res 研究完的、own 买下的、rp[key] 攒着的研究点、cur[系:树] 正在研究的、lineup[系] 出击阵容（最多 5 辆）、nat 现在用哪个系、
--     free[系] 没处放的研究点（研究完多出来的、没选研究目标时挣的）；P.data.codes[码的编号] 兑换过的码（不写给客户端）
--   白送的只有每系每棵树一辆起步车（TechTree TT.starter，用户 11-26「每个系从只给一辆最基础的坦克开始」），别的研究完再拿金币买
--   整备（用户 11-27「整个给载具配置武器的系统 做的很粗糙」）：load[键] 飞机 / 直升机的挂载 { p 照哪套预设改的, l 每个挂点挂什么, f 内油几成 }
--     （出击、试驾都按它挂；没存过的按第一套预设、满内油）、ammo[键] 地面车配弹 { 弹种 = 几发 }、skin[键] 涂装 { c 涂装, n 战术号码, e 国徽 }
--     ——ammo / skin 这一步只存着、读档时校验（整备的弹药、涂装页以后用）
--   给客户端：玩家属性 Tree（JSON，变了才写）；动作（客户端 Act）：treeResearch / treeBuy / treeLineup / treeNat / treeLoad / deployVeh
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
  local BAL = require(RS:WaitForChild("Ballistics"))   -- 弹种（存档里的配弹只认认得的弹）
  local SKS = require(RS:WaitForChild("WtSkins"))      -- 涂装（存档里的涂装只认认得的）
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
  --   load[车] = { p = 预设, l = { 每个挂点的武器或 false }, f = 内油 }、ammo[车] = { 弹种 = 几发 }、skin[车] = { c, n, e }（见文件头「整备」）
  --   sets[车] = { ["1"～"3"] = { l, f } }：整备挂载页的三个「我的方案」（键写成字符串：JSON 不认有空洞的数组）
  local function blank() return { res = {}, own = {}, rp = {}, cur = {}, lineup = {}, nat = "cn", free = {}, mods = {}, crew = {}, load = {}, ammo = {}, skin = {}, sets = {} } end
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

  ---------------------------------------------------------------- 整备存档（挂载、配弹、涂装）：客户端发来的、读档读到的都过一遍这里
  -- 挂载：只收科技树里的飞机 / 直升机、有挂点的；每个挂点只能挂它能挂的（AD.cleanLoad，不对的清成空），内油 0.25～1（AD.cleanFuel）；
  --   p 是照哪套预设改的（认得的预设才记；改过几个挂点照样记着，界面写「（已改）」）。没给 l 只给了 p：按那套预设展开
  local function cleanTreeLoad(it, v)
    local d = it and (it.branch == "air" or it.branch == "heli") and AD.get(it.play)
    if not d or not d.st or #d.st == 0 or type(v) ~= "table" then return nil end
    local p = nil
    if type(v.p) == "string" then
      for _, x in ipairs(d.presets or {}) do if x.key == v.p then p = v.p end end
    end
    local l = (type(v.l) == "table") and AD.cleanLoad(d, v.l) or AD.presetLoad(d, p)
    return { p = p, l = l, f = AD.cleanFuel(v.f) }
  end
  -- 配弹：认得的弹种、0～200 发、最多 8 种（同 Wt.lua wtAmmoSet）
  local function cleanTreeAmmo(it, v)
    if not it or it.branch ~= "ground" or type(v) ~= "table" then return nil end
    local c, n = {}, 0
    for k, x in pairs(v) do
      if type(k) == "string" and BAL.AMMO[k] and type(x) == "number" and n < 8 then
        c[k] = math.clamp(math.floor(x), 0, 200)
        n += 1
      end
    end
    return (n > 0) and c or nil
  end
  -- 涂装：认得的涂装（标准涂装不记）、战术号码 0～999、贴不贴国徽（同 WtMatch.lua wtSkinSet）
  local function cleanTreeSkin(it, v)
    if not it or type(v) ~= "table" then return nil end
    local c = (type(v.c) == "string" and SKS.CAMO[v.c] and v.c ~= "std") and v.c or nil
    local n = tonumber(v.n)
    if n then n = math.clamp(math.floor(n), 0, 999) end
    return { c = c, n = n, e = v.e == true }
  end
  -- 我的方案（整备挂载页左栏的三个）：每个照挂载那样清（AD.cleanLoad / cleanFuel），只认 "1"～"3"；一个都没有返回 nil
  local function cleanTreeSets(it, v)
    if type(v) ~= "table" then return nil end
    local out, n = {}, 0
    for i = 1, 3 do
      local x = v[tostring(i)] or v[i]
      local o = (type(x) == "table") and cleanTreeLoad(it, { l = x.l, f = x.f }) or nil
      if o and type(x.l) == "table" then
        out[tostring(i)] = { l = o.l, f = o.f }
        n += 1
      end
    end
    return (n > 0) and out or nil
  end
  -- 这一辆存的挂载（出击、试驾用）：挂载表、内油；没存过（或者不是飞机）返回 nil（Air.lua 按第一套预设、满内油）
  local function treeLoadOf(P, key)
    local t = T(P)
    local it = type(key) == "string" and TT.byKey[key] or nil
    local v = t and t.load and it and t.load[key]
    local o = v and cleanTreeLoad(it, v)
    if not o then return nil, nil end
    return o.l, o.f
  end
  G.treeLoadOf = treeLoadOf
  -- 存挂载（整备的挂载页 / 挂载编辑器 Hangar.lua 的「保存」）：key 科技树的键，load 每个挂点的武器（false 是空），preset 照哪套预设改的，fuel 内油几成；
  --   quiet：整备的挂载页改一下存一下（即时存），不弹「挂载已保存」。没买的也能存（科技树里随便哪一架都能试驾）；不是飞机、没有挂点的不理
  G.ACT.treeLoad = function(P, key, load, preset, fuel, quiet)
    local t = T(P)
    local it = type(key) == "string" and TT.byKey[key] or nil
    if not t or not it then return end
    local o = cleanTreeLoad(it, { l = load, p = preset, f = fuel })
    if not o then return end
    t.load = t.load or {}
    t.load[key] = o
    if P.pl and quiet ~= true then G.msg(P.pl, "info", "tree.loadSaved", { k = "tree." .. key }) end
    publish(P)
    save(P)
  end
  -- 我的方案：slot 1～3；load 是 false 清掉这一格
  G.ACT.treeLoadSet = function(P, key, slot, load, fuel)
    local t = T(P)
    local it = type(key) == "string" and TT.byKey[key] or nil
    slot = tonumber(slot)
    if not t or not it or not slot or slot ~= math.floor(slot) or slot < 1 or slot > 3 then return end
    t.sets = t.sets or {}
    local cur = t.sets[key] or {}
    if load == false then
      cur[tostring(slot)] = nil
    else
      if type(load) ~= "table" then return end
      local o = cleanTreeLoad(it, { l = load, f = fuel })
      if not o then return end
      cur[tostring(slot)] = { l = o.l, f = o.f }
    end
    t.sets[key] = next(cur) and cur or nil
    publish(P)
    save(P)
  end

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
    -- 整备：挂载、配弹、涂装——只留认得的车，内容按上面 cleanTree* 再过一遍（改过挂点、弹种、涂装表以后，旧档里不对的清掉）
    for f, clean in pairs({ load = cleanTreeLoad, ammo = cleanTreeAmmo, skin = cleanTreeSkin, sets = cleanTreeSets }) do
      for k, v in pairs(type(src[f]) == "table" and src[f] or {}) do
        local it = type(k) == "string" and TT.byKey[k] or nil
        local o = it and clean(it, v)
        if o then t[f][k] = o end
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
    local mk = ((W.modeK or {})[G.wtModeNow and G.wtModeNow() or "rb"]) or 1   -- 历史 ×1.3（战雷：越真实奖励越多）
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
  -- 只有历史一种模式（用户 11-27「把全真模式去掉」「历史和街机就保留一个吧」）：不再投票，workspace 属性 WtMode 一直是 rb
  --   （客户端很多地方按它判断；老客户端还会发 wtModeVote，收了不理）
  function G.wtModeNow()
    if workspace:GetAttribute("WtMode") ~= "rb" then pcall(function() workspace:SetAttribute("WtMode", "rb") end) end
    return "rb"
  end
  G.ACT.wtModeVote = function() end
  G.wtModeNow()
  G.on("roundStart", function() G.wtModeNow() end)

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
  local DRONE_HELI = { "ah64e", "ka52", "mi28", "mi24" }   -- 直-10 11-27 删了（原模型是扒的），换成卡-52
  -- 地面试驾的靶车：射击方向多少米、往右多少米、横着来回开的半程（米，没有就不动）
  --   训练场（11-26 晚）：每人一条靶道（960 格 ≈ 340 米宽），横着偏的、来回开的都收在自己的靶道里（最多偏 150 米）
  local RANGE = { { 300, -40 }, { 500, 60 }, { 700, -70, 70 }, { 1000, 30 }, { 1300, 60, 90 }, { 1600, -110 }, { 2000, 50 } }
  -- 靶机：绕哪儿转（射击方向多少米、往右多少米）、半径（米）、离地多高（米）、速度（米 / 秒）、直升机
  local SKY = { { 1300, -400, 900, 420, 170 }, { 1800, 500, 1300, 650, 210 }, { 900, 250, 450, 70, 32, true } }
  -- 飞机试驾的地面靶：离靶机中心多少米（往前、往右）
  local AIRGROUND = { { 0, -150 }, { 40, -50 }, { -30, 60 }, { 60, 160 }, { 500, 0 }, { 520, 120 } }
  -- 飞机试驾在空中出生（跑道上滑不起来的大飞机、摆不到跑道上的兜底）：固定翼退到离靶区中心几秒航程的地方、朝北进场（最多退 12000 格，还在训练场的地形里）——
  --   炸弹从 1200 格高平飞投下去往前飞 9.7 秒：轰-6K / B-2 出来九秒多才到投弹点，有时间开轰炸瞄准镜对准；MQ-9 慢，按秒算只退 4900 格
  local RUNIN = 18
  local M = 2.8   -- 一米多少格
  local function flatOk(x, z)
    local Map = G.Map
    return Map.height(x, z) > 2 and (not Map.slope or Map.slope(x, z) < 0.3)
  end
  -- 训练场（MapRange）：第几个在试驾的人用第几条靶道
  local RangeMap = G.Map.Range or require(RS:WaitForChild("MapRange"))
  -- 在哪试驾（一次试驾定一处，记在 s.rm / s.where）：
  --   · 训练场服务器（Places.lua，用户 11-28「训练场 还有各种地图单独做成一个服务器」）：开的就是雪山图，在这张图上试
  --     （G.testRange，SnowRange.lua：同 MapRange 的几个函数，外加按地形挑好的靶车位置）
  --   · 别的服务器、战场就是雪山图（用户 11-28「试驾你就让我在雪山地图试驾吧搞点靶车」，晚上又问「为什么训练场现在还是没有雪山地图」——
  --     原来只有单独发布的训练场地点才在雪山上试，Studio、只发布了一个地点的照旧去绿草的训练场区块）：这张图上没在打一局（匹配中、结算）
  --     就在战场这张雪山图上试（G.battleRange，init.server.lua 建图以后算：同样每人一条靶道、靶车、靶机）；正在打一局的时候
  --     （两头基地出电脑车，靶道就在基地边上）才退回训练场区块（那时候才建）；一局要开打了，在这张图上试驾的人回机库（下面 matchFound）
  --   · 战场不是雪山：训练场区块（MapRange）
  local function snowMapFree()
    local R0 = G.round
    return not (R0 and (R0.phase == "prep" or R0.phase == "battle"))
  end
  -- 战场是不是雪山图（开服时图还没定：只剩雪山这一张就算是——马上就定成它）
  local function battleSnow()
    if G.placeRole == "range" then return false end
    local id = G.mapId
    if not id and G.Map.ids and #G.Map.ids == 1 then id = G.Map.ids[1] end
    return id ~= nil and id == (Config.RangeMap or "snow")
  end
  G.testBattleSnow = battleSnow
  local function chooseRM()   -- 靶场、哪一种（"range" 训练场服务器 / "battle" 战场的雪山图 / "zone" 训练场区块）、好了没有
    if G.placeRole == "range" then return G.testRange or RangeMap, "range", G.testRange ~= nil and G.rangeReady == true end
    if battleSnow() and snowMapFree() then return G.battleRange or RangeMap, "battle", G.battleRange ~= nil and G.worldReady == true end
    return RangeMap, "zone", G.rangeReady == true
  end
  G.testWhere = function() local _, w, ok = chooseRM() return w, ok end   -- 测试用
  local function RM(s) return (s and s.rm) or G.testRange or RangeMap end
  -- 两个人几乎同时点试驾（用户 11-28「如果这个游戏里有两个人同时选择开始试驾怎么办」）：靶道号原来在点的那一刻算、人生出来（零点几秒，
  --   远处还要等流式加载几秒）以后才登记进 tests——这中间第二个人点，两个人分到同一条靶道，两辆车生在一起。现在点的那一刻先占着（reserved），
  --   登记进 tests 就放开；没生出来（出生失败、掉线）的 30 秒后不算
  local reserved = {}   -- [P] = { i = 靶道号, t = 什么时候占的 }
  local function testIndex(P)
    local used = {}
    for q, s in pairs(tests) do if q ~= P and s.idx then used[s.idx] = true end end
    local t = now()
    for q, r in pairs(reserved) do
      if q ~= P and t - r.t < 30 and q.pl and q.pl.Parent then used[r.i] = true elseif t - r.t >= 30 or not (q.pl and q.pl.Parent) then reserved[q] = nil end
    end
    for i = 0, 63 do if not used[i] then return i end end
    return 0
  end
  G.testReserved = function() return reserved end   -- 测试用
  -- 第 idx 个在试驾的人的车位：靶道够分就一人一条；比靶道还多（同一个服务器里八个以上同时开坦克试驾）的，在同一条靶道里往旁边挪开
  --   （雪山训练场 SnowRange 有 16 条：两头基地各一排）
  local function testSpot(rm, idx)
    local n = rm.LANES
    local p, d = rm.lane(idx % n + 1)
    local row = (idx // n) % 3
    if row > 0 and rm.LANE_W then
      local right = Vector3.new(-d.Z, 0, d.X)
      local q = p + right * (((row == 1) and 0.3 or -0.3) * rm.LANE_W)
      p = Vector3.new(q.X, G.Map.height(q.X, q.Z), q.Z)
    end
    return p, d
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
    pcall(function() P.pl:SetAttribute("TestDriveAt", nil) end)   -- 试驾完了：客户端回到这一局的钟点（DayNight 的 testDay）
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
    -- 雪山上的训练场（SnowRange）：圈收进河谷里（半径最多 SKY_R 米、圈心挪到河谷中线），飞得比圈上最高的地形高——两边七八百米的雪山
    local rm = RM(s)
    if rm.SKY_R then
      r = math.min(r, rm.SKY_R)
      if rm.skyCenter then c = rm.skyCenter(c) end
    end
    local R = r * M
    local hY = h * M
    if rm.skyAlt then hY = rm.skyAlt(c, R, hY) end
    local a = (i * 2.1) % (2 * math.pi)
    local p = Vector3.new(c.X + math.cos(a) * R, G.Map.height(c.X, c.Z) + hY, c.Z + math.sin(a) * R)
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
  -- 靶场还没好（开服头一会儿雪山图还在生成、训练场区块还在后台建）：记下来，好了自动接着试（不用再点一次；一个人只等一辆，再点换成新点的）
  local testWait = {}   -- [P] = 要试的那一辆
  local function testLater(P, key)
    local first = testWait[P] == nil
    testWait[P] = key
    if not first then return end
    task.spawn(function()
      local t0 = now()
      while now() - t0 < 180 do
        task.wait(0.5)
        if G.P[P.pl] ~= P or not testWait[P] then break end
        local _, w, ok = chooseRM()
        if ok then break end
        if w == "zone" and G.ensureRange then G.ensureRange() end   -- 等雪山图的时候这张图开打了：退回训练场区块（这时候才建）
      end
      local k = testWait[P]
      testWait[P] = nil
      if k and G.P[P.pl] == P and not P.alive and not (G.inMatch and G.inMatch(P)) then
        local _, _, ok = chooseRM()
        if ok then G.ACT.testDrive(P, k) end
      end
    end)
  end
  G.testWaiting = function(P) return testWait[P] end   -- 测试用
  -- 战场这张雪山图要开打一局了（匹配到了）：在这张图上试驾的人回机库——靶道就在两头基地边上，电脑车、出击的人都从那儿出来
  --   （同长按 H 回机库：车、靶车、靶机收走，不算阵亡，马上能再点试驾——那时候这张图在打，退回训练场区块）
  local function testEndBack(P)
    local s = tests[P]
    if not s then return end
    local e, char = s.veh, P.char
    P.char, P.alive, P.vehicle = nil, false, nil   -- 先断开：角色的 Died 不算阵亡（Round.lua onDied 只认 P.char）
    if e and P.remote == e then P.remote = nil end
    P.canDeployAt = now()
    P.dmgLog = {}
    testClean(P)
    if e and e.alive then pcall(G.removeEnt, e) end
    if char and char.Parent then char:Destroy() end
    pcall(function() P.pl.Character = nil end)
    G.msg(P.pl, "info", "tree.testMatch")
    if G.pushOne then G.pushOne(P) end
  end
  G.on("matchFound", function()
    for Q, s in pairs(tests) do
      if s.where == "battle" then G.try("试驾让出雪山图", testEndBack, Q) end
    end
  end)
  G.on("left", function(P) testWait[P] = nil end)
  local function testDriveNow(P, key)
    local it = type(key) == "string" and TT.byKey[key]
    if not it or P.alive or G.pve or not G.ACT.deploy then return end
    -- 局内（这一局算他的、准备 / 战斗阶段：机库是局内选车页，Round.lua G.inMatch）不能试驾，同战雷的出击页：TechUI 在局内选车页藏了「试驾」、
    --   科技树也不开，服务器这里也拦——原来只藏了按钮，客户端直接发 testDrive 照样能半路去训练场（试驾不看兵力、出生点：Round.lua deploy 的 P.testDeploy）
    if G.inMatch and G.inMatch(P) then return end
    if now() < (P.canDeployAt or 0) then G.msg(P.pl, "info", "tree.waitDeploy", math.ceil((P.canDeployAt or 0) - now())) return end
    local air = it.branch == "air" or it.branch == "heli"
    local heli = it.branch == "heli"
    local tl, tf = treeLoadOf(P, key)   -- 试驾也按机库里存的挂载、内油（整备；没存过是 nil：第一套预设、满内油）
    -- 有训练场服务器（Places.lua）：传送过去试（带着这一辆，到了自动坐进去）；传不过去就在本服务器试（下面 chooseRM 挑在哪）
    if G.teleport and G.placeFor and G.placeFor("range") then
      local function here()   -- 传送没成功：本服务器的靶场好了就接着试（不用再点一次）
        G.placeTpOffFor = G.placeTpOffFor or {}
        G.placeTpOffFor[P.pl] = true
        G.msg(P.pl, "info", "place.rangeHere")
        local _, where0, ok0 = chooseRM()
        if ok0 then
          if G.P[P.pl] == P and not P.alive then testDriveNow(P, key) end
        else
          if where0 == "zone" and G.ensureRange then G.ensureRange() end
          testLater(P, key)
        end
      end
      if not (G.placeTpOffFor and G.placeTpOffFor[P.pl]) and G.teleport(P, "range", { td = key }, here) then return end
    end
    local rm, where, ready = chooseRM()
    if not ready then   -- 开服头一会儿：雪山图还在生成 / 训练场区块还在后台建——好了自动接着试
      if where == "zone" and G.ensureRange then G.ensureRange() end   -- 战场这张雪山图上正在打一局：这时候才建训练场区块
      G.msg(P.pl, "info", (where == "zone") and "tree.rangeBusy" or "tree.snowBusy")
      testLater(P, key)
      return
    end
    testWait[P] = nil
    if where == "zone" and battleSnow() then G.msg(P.pl, "info", "tree.rangeMatch") end   -- 雪山图上正在打一局：这次在训练场区块试
    local idx = testIndex(P)
    reserved[P] = { i = idx, t = now() }   -- 先占着（见 testIndex）
    -- 出车的地方：车在第 idx 条靶道的射击线上、飞机在跑道东头、直升机在直升机坪
    local spawnAt, spawnDir
    if heli then spawnAt, spawnDir = rm.heliPad(idx)
    elseif air then spawnAt, spawnDir = rm.runwayStart(idx)
    else spawnAt, spawnDir = testSpot(rm, idx) end
    local all = {}   -- 试驾：改装全装上（下面 applyFx）
    for _, m in ipairs(WM.list(it)) do all[m.key] = true end
    local fx = WM.fx(it, all)
    -- 跑道上滑不起来的固定翼直接在空中出生（用户 11-27「飞机试驾不了」：满油满弹的轰-6K、B-2 推满油门照样冲出训练场 3600 格的跑道，
    --   B-2 冲到训练场铺的地形外面才离地）。不按型号列名单：按飞行物理静态估一下离地要滑多远（AirDefs.takeoffRun，照客户端 Fly.lua 地上那段
    --   推满油门、到抬头速度拉杆；满油、默认挂载、改装全装的推力），比起飞位往西剩下的跑道（RangeMap.runwayLeft）的九成五还长
    --   （留一点：拉杆晚一两秒也不冲出去）就不摆在跑道上，同下面「摆不到跑道上」那条在空中出来。估不出来的（没有飞行物理）照旧在跑道上
    local sky = false
    if air and not heli then
      local okR, run, lifted = pcall(AD.takeoffRun, AD.get(it.play), { treeKey = it.key, thrK = fx.thr, h = spawnAt.Y })
      if okR and run and (not lifted or run > rm.runwayLeft(idx) * 0.95) then sky = true end
    end
    local function go()
      if not P.alive or not P.char then return end
      testClean(P)
      local s = { P = P, idx = idx, dummies = {}, drones = {}, foe = (P.team == "atk") and "def" or "atk", air = air, rm = rm, where = where }
      local d = air and AD.get(it.play)
      local skyAt, skyV   -- 空中出生的位置、速度
      if air then
        -- 飞机、直升机：靶区在挡弹墙北面（空中靶区，MapRange.AIRTGT），朝北摆靶
        s.base, s.dir = rm.airTarget(), Vector3.new(0, 0, -1)
        -- 空中出生（上面估的跑道上滑不起来 sky、下面摆不到跑道 / 直升机坪上的兜底）：朝北、带 0.8 倍军推最大速度（客户端 Fly.lua 空中出发也按这个）；
        --   固定翼往南退到离靶区中心 RUNIN 秒航程的地方、朝北进场——原来在靶区中心正上方出来：地面靶在正前方 0～1460 格，1200 格高、
        --   600 格 / 秒平飞投炸弹要提前 5000 多格松手，一出来就已经飞过了靶子，轰炸机掉头半径又有好几公里；现在轰-6K 出来九秒多才到投弹点。
        --   直升机照旧在靶区上方 140 格悬停出来
        skyV = heli and 0 or (((d and d.vMil) or 200) * 0.8)
        local b0 = s.base - s.dir * math.min(skyV * RUNIN, 12000)
        skyAt = Vector3.new(b0.X, G.Map.height(b0.X, b0.Z) + (heli and 140 or (W.airSpawnH or 1200)), b0.Z)
      end
      -- 流式加载：先请服务器把出生那一片送过去（人在战场那边出生的，十万格外的地形、零件这时还没到客户端）——空中出生的送空中那一片
      --   （原来一直送跑道东头，离空中出生的地方一万多格）；无人机也一样：画面是无人机那边，操作员被钉在原地（Air.lua seat），不会掉下去
      if G.streamAround then G.streamAround(P.pl, sky and skyAt or spawnAt, 8) end
      if not P.alive or not P.char then return end
      local e
      local aloft = false   -- 在空中出生的（sky、兜底）
      if air then
        local pos = Vector3.new(spawnAt.X, G.Map.height(spawnAt.X, spawnAt.Z) + ((d and d.gearH) or 5), spawnAt.Z)
        if G.spawnAircraft and not sky then
          local okS, ee = pcall(G.spawnAircraft, P.team, it.play, CFrame.lookAt(pos, pos + spawnDir), tl, P, tf)
          if okS then e = ee end
        end
        if not e and G.spawnAircraftAir then   -- 跑道上滑不起来（sky）、摆不到跑道 / 直升机坪上：在空中出来
          e = G.spawnAircraftAir(P.team, it.play, CFrame.lookAt(skyAt, skyAt + s.dir), tl, P, tf, skyV)
          aloft = e ~= nil
        end
      else
        s.base, s.dir = spawnAt, spawnDir
        e = G.spawnGroundVeh(P.team, it.play, CFrame.lookAt(s.base, s.base + s.dir), false, P, nil)
      end
      if not e then reserved[P] = nil return end
      tests[P] = s
      reserved[P] = nil   -- 登记进 tests 了：不用再占
      P.inTest = true
      s.veh = e
      e.testDrive, e.noScore, e.treeKey = true, true, key
      e.model:SetAttribute("TreeKey", key)
      e.model:SetAttribute("TestDrive", true)
      applyFx(e, air, WM.fx(it, all), nil)   -- 试驾：改装全装上（all 在上面）
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
        -- 雪山训练场：按地形挑好、看得见的位置（同一条靶道挤了两个人的，往旁边挪开的那个照原来的偏移摆，不跟第一个人的靶车摆在一处）
        local tg = rm.targets and (idx < rm.LANES) and rm.targets(idx % rm.LANES + 1, RANGE)
        if tg then
          for _, t in ipairs(tg) do dummyAt(s, t.k, t.pos, -s.dir, t.swing) end
        else
          for i, r in ipairs(RANGE) do
            local p = at(r[1], r[2])
            dummyAt(s, i, Vector3.new(p.X, G.Map.height(p.X, p.Z), p.Z), -s.dir, r[3])
          end
        end
        for i, k in ipairs(SKY) do droneAt(s, i, at(k[1], k[2]), k[3], k[4], k[5], k[6]) end
      end
      P.char:PivotTo(e.root.CFrame * CFrame.new(0, 2, 0))
      if G.ACT.enterVeh then G.ACT.enterVeh(P, e.id) end
      -- 无人机：人拿着平板站着遥控（Air.lua seat 不挪人、把人钉住）——操作员挪到起飞位旁边、跑道南边的草地上（MapRange.runwaySide），面朝跑道：
      --   空中出生的别留在天上（收起平板就掉下来）；在跑道上出生的也别站在起飞位上（上面 PivotTo 到了机身上：飞机滑走以后人还钉在跑道上，
      --   前面几个起飞位的飞机滑跑正好从他身上穿过去）
      if e.def and e.def.drone and P.remote == e and P.char then
        local op = rm.runwaySide(idx) + Vector3.new(0, 3, 0)
        P.char:PivotTo(CFrame.lookAt(op, op + Vector3.new(0, 0, -1)))
      end
      -- 提示在哪出来：空中出生分两种原因——估出来跑道上滑不起来（sky：testOnSky）、摆不到跑道 / 直升机坪上的兜底（testInAir；原来兜底也说
      --   「满油满弹滑不起来」）；直升机停在直升机坪上（testOnPad；原来和固定翼一样说「在跑道上，推油门起飞」）
      local msg = (where ~= "zone") and "tree.testOnSnow" or "tree.testOn"   -- 雪山图上：靶车按地形摆，多在几百米内（SnowRange）
      if aloft then msg = sky and "tree.testOnSky" or "tree.testInAir"
      elseif heli then msg = "tree.testOnPad"
      elseif air then msg = "tree.testOnAir" end
      G.msg(P.pl, "info", msg, it.name)
    end
    P.testDeploy = true   -- Round.lua deploy：试驾不受出生点 / 准备阶段 / 兵力限制（用户 11-26「训练场目前没发试驾飞机了」）
    -- 人直接生在训练场出车的地方（11-28：训练场开服就建，战场的图还没定、没有出生点时主界面也能试驾；原来先生在战场的基地、再挪过来）
    P.testSpawnCF = CFrame.new(spawnAt + Vector3.new(0, 4, 0))
    -- 客户端 DayNight：试驾一直是白天（用户 11-28 夜「然后训练场改成持续百天吧」）——人先生出来、车后到，这一下也按白天算
    --   （不然夜里出生自动打开夜视仪，坐进车又「天亮了」收起来）；收车时（testClean）去掉，没出成车的 15 秒后不算
    pcall(function() P.pl:SetAttribute("TestDriveAt", workspace:GetServerTimeNow()) end)
    G.ACT.deploy(P, "crew", air and "baseAir" or "base", go)
    P.testDeploy, P.testSpawnCF = nil, nil
  end
  -- 同一个人一次只走一趟：雪山图上的靶道第一次用到要按地形现算（SnowRange，会等几帧）、出车 LoadCharacter 也要等——
  --   这中间又点了一下、或者靶场好了自动接着试（testLater）撞上，都不理（不然出两次车、占两条靶道）
  G.ACT.testDrive = function(P, key)
    if P.testBusy and now() - P.testBusy < 10 then return end
    P.testBusy = now()
    local ok, err = pcall(testDriveNow, P, key)
    P.testBusy = nil
    if not ok then error(err, 0) end
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
      --   挂载、内油按机库里存的（整备；没存过是 nil：Air.lua 按第一套预设、满内油）
      local tl, tf = treeLoadOf(P, key)
      okS, e = pcall(function() return G.padSpawnAt and G.padSpawnAt(P, p, tl, vid, tf) end)
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
