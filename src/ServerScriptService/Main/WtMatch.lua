-- Roblox全面大战场（服务器）——战雷式对局（用户 11-24 夜「把整个游戏做成战雷」③：对局玩法）
--   沙海本来就是征服模式（据点、两边兵力、据点少的一边掉兵力、阵亡扣兵力），这里补上战雷的：
--   · 重生点数 SP：每局每人从 Config.Wt.sp0 起，第一辆车不要 SP（战雷那样），以后出车按 Config.WtCost 花——
--     坦克 300、步战车 200、防空 220、自行火炮 260、战斗机 450、轰炸机 550、无人机 280、武装直升机 380、运输直升机 240、舰艇 400，
--     这一局每多出过一辆贵两成五；得分攒 SP（每分 perScore：击毁一辆车 200 分 → 100 SP，占点 300 分 → 150 SP），封顶 spMax；
--     步兵出生不要 SP
--   · 出击阵容：一局最多开 Config.Wt.lineup 种车（先开出来的那几种），每种出 1 + backup 次（备用）
--   · 出车前查（Depots.lua spawnAt 问 G.wtSpawnOk），出了车记账（G.wtSpawned）；车被打掉记一笔（Ents 的 entDied）
--   · 结算：每人击毁地面车辆 vk、击落飞机 ak、这一局攒了多少 SP（boardState 带上，客户端 WtMatch.lua 画战雷那样的结算页）
--   PvE 关卡不收 SP（关卡自己定兵力）；准备阶段出车不花 SP、也不算免费那一辆，但进阵容
local RS = game:GetService("ReplicatedStorage")

local WtMatch = {}

function WtMatch.init(G)
  local Config = G.Config
  local VD = require(RS:WaitForChild("VehDefs"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local W = Config.Wt or {}

  local function on() return W.on ~= false and not G.pve end
  -- 每人这一局的账（换了一局重新开）
  local function S(P)
    local n = G.round and G.round.n or 0
    local s = P.wtm
    if not s or s.round ~= n then
      s = { round = n, sp = W.sp0 or 0, earned = 0, paid = 0, free = true, ln = {}, order = {}, lost = {}, vk = 0, ak = 0 }
      P.wtm = s
    end
    return s
  end
  G.wtState = S

  local function catOf(vid, kind)
    if kind == "ship" then return "ship" end
    local d = AD.get(vid)
    if d then return d.cat end   -- jet / heli
    d = VD.get(vid)
    return d and d.cat or "tank"
  end
  -- 这辆车现在出要多少 SP（准备阶段、第一辆、PvE：0）
  function G.wtCost(P, vid, kind)
    if not on() then return 0 end
    local R = G.round
    if not R or R.phase ~= "battle" then return 0 end
    local s = S(P)
    if s.free then return 0 end
    return Config.WtCost(vid, catOf(vid, kind), s.paid)
  end
  -- 能不能出这辆：阵容满了、备用用完了、SP 不够都说一声
  function G.wtSpawnOk(P, vid, kind)
    if not on() or not P or not P.pl or not vid then return true end
    local s = S(P)
    local n = s.ln[vid] or 0
    if n == 0 and #s.order >= (W.lineup or 5) then
      G.msg(P.pl, "bad", "wt.lineupFull", W.lineup or 5)
      return false
    end
    if n >= 1 + (W.backup or 1) then
      G.msg(P.pl, "bad", "wt.noBackup", { k = "veh." .. vid }, n)
      return false
    end
    local c = G.wtCost(P, vid, kind)
    if c > s.sp then
      G.msg(P.pl, "bad", "wt.needSp", c, math.floor(s.sp))
      return false
    end
    return true
  end
  function G.wtSpawned(P, vid, kind, e)
    if not P or not P.pl or not vid then return end
    if e then e.wtOwner, e.wtVid = P, vid end
    if not on() then return end
    local s = S(P)
    local c = G.wtCost(P, vid, kind)
    if (s.ln[vid] or 0) == 0 then table.insert(s.order, vid) end
    s.ln[vid] = (s.ln[vid] or 0) + 1
    if G.round and G.round.phase == "battle" then
      if s.free then s.free = false else s.paid += 1 end
      s.sp = math.max(0, s.sp - c)
    end
    G.pushOne(P)
  end

  -- 得分攒 SP（只在开战以后；结算时的胜负加分不算）
  local baseAdd = G.addScore
  G.addScore = function(P, n)
    baseAdd(P, n)
    if not on() or not P or not P.pl or (n or 0) <= 0 then return end
    local R = G.round
    if not R or R.phase ~= "battle" then return end
    local s = S(P)
    local before = s.sp
    s.sp = math.min(W.spMax or 3000, s.sp + n * (W.perScore or 0.5))
    s.earned += s.sp - before
  end

  -- 车被打掉：车主那一型记一笔「已毁」；打掉它的人记击毁地面 / 击落空中
  G.on("entDied", function(e, src)
    local P = e.wtOwner
    if P and e.wtVid then
      local s = S(P)
      s.lost[e.wtVid] = (s.lost[e.wtVid] or 0) + 1
    end
    local K = src and src.P
    if K and K.pl and G.P[K.pl] == K and e.cat ~= "inf" and e.cat ~= "fort" and e.team ~= K.team then
      local s = S(K)
      if e.cat == "air" then s.ak += 1 else s.vk += 1 end
    end
  end)

  -- 推给自己的客户端（Round.lua personal）：SP、阵容（出过几次、毁了几次）、免费那一辆还在不在
  function G.wtPersonal(P)
    if not on() then return nil end
    local s = S(P)
    return { sp = math.floor(s.sp), free = s.free, paid = s.paid, order = s.order, ln = s.ln, lost = s.lost,
      max = W.lineup or 5, backup = W.backup or 1, earned = math.floor(s.earned), vk = s.vk, ak = s.ak }
  end
  -- 战况表、结算页的一行（Round.lua boardState）
  function G.wtBoard(P, row)
    local s = P.wtm
    if s and s.round == (G.round and G.round.n) then row.vk, row.ak, row.sp = s.vk, s.ak, math.floor(s.earned) end
  end
end

return WtMatch
