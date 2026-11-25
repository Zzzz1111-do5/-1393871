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
  local TT = require(RS:WaitForChild("TechTree"))
  local W = Config.Wt or {}
  local LINEUP = W.lineup or 5

  local function save(P) if G.saveData then task.spawn(G.saveData, P) end end
  local function blank() return { res = {}, own = {}, rp = {}, cur = {}, lineup = {}, nat = "cn", free = {} } end
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
    local rp = math.floor(base * (won and 1.3 or 1))
    local used = P.treeUsed or {}
    local brs = {}
    for _, br in ipairs(TT.BRANCHES) do if used[br] then table.insert(brs, br) end end
    if #brs == 0 then brs = { "ground" } end
    local each = math.floor(rp / #brs)
    for _, br in ipairs(brs) do
      local key = t.cur[t.nat .. ":" .. br]
      if key then addRp(P, key, each) else t.free[t.nat] = (t.free[t.nat] or 0) + each end
    end
    P.treeUsed = {}
    if rp > 0 and P.pl then G.msg(P.pl, "good", "tree.rp", rp) end
    publish(P)
    return rp
  end

  ---------------------------------------------------------------- 出击：直接坐进车里 / 飞机里

  -- 本队这一类（地面 / 空中）的召唤位：在自己基地里、开着的、空着的先
  local function padFor(team, air)
    local best
    for _, p in ipairs(G.pads or {}) do
      local okKind = air and (p.kind == "air" and not p.heli) or (not air and p.kind == "veh")
      if okKind and p.team == team and (not G.padOpen or G.padOpen(p, team)) then
        best = best or p
        if p.summon then return p end
      end
    end
    return best
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
    local p = padFor(P.team, air)
    if not p then G.msg(P.pl, "bad", "ui.padLocked") return end
    local vid = it.play
    local kind = air and "air" or "veh"
    if G.wtSpawnOk and not G.wtSpawnOk(P, vid, kind) then return end
    local function go()
      if not P.alive or not P.char or P.vehicle then return end
      -- 人挪到召唤台边上（召唤台按「人在终端旁边」查），再按召唤台生成、坐进去
      local hrp = P.char:FindFirstChild("HumanoidRootPart")
      if hrp then P.char:PivotTo(CFrame.new(p.term + Vector3.new(0, 3, 0))) end
      P.padT = 0
      P.treeSpawn = true
      local okS, e = pcall(function() return G.padSpawnAt and G.padSpawnAt(P, p, nil, vid) end)
      P.treeSpawn = nil
      if not okS then warn("[科技树] 出击出错：" .. tostring(e)) e = nil end
      if not e then return end
      e.treeKey = key
      e.model:SetAttribute("TreeKey", key)   -- 客户端名牌、击杀提示按科技树的名字写（借来的型号也写自己的名字）
      P.treeUsed = P.treeUsed or {}
      P.treeUsed[it.branch] = true
      P.char:PivotTo(e.root.CFrame * CFrame.new(0, 2, 0))
      if G.ACT.enterVeh then G.ACT.enterVeh(P, e.id) end
      if P.vehicle ~= e then   -- 没坐上（召唤位上有东西挡着之类）：车留着，人在旁边
        G.msg(P.pl, "info", "tree.walkIn")
      end
    end
    if P.alive and P.char then
      go()
    elseif G.ACT.deploy then
      G.ACT.deploy(P, "crew", air and "baseAir" or "base", go)
    end
  end
end

return Tech
