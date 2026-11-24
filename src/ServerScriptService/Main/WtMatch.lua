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

  ---------------------------------------------------------------- 侦察（战雷：轻型车对着准星下的敌车按键，全队看得见它 30 秒）
  --   用户 11-24 夜「完全弄成战雷」：照战雷 wiki 的侦察——轻型车（步战车、装甲车、防空车）才能侦察；准星附近、看得见的敌方车辆；
  --   全队在屏幕上、小地图上看得见它 30 秒（Weapons.lua 的 spotted，同 Z 键标记）；同一个目标 30 秒里只能被侦察一次；
  --   侦察到的车 30 秒里被别人打掉：侦察的人「侦察助攻」加分、多一次火炮支援（战雷街机就是这样）
  local now = os.clock
  local SC = W.scout or { range = 4200, cone = 2.5, time = 30, relock = 30, cd = 2, kill = 60 }
  local SCOUT_CAT = { apc = true, aa = true }
  local function myVeh(P)
    local e = P and P.vehicle
    if not P or not P.alive or not e or not e.alive or not e.root or e == P.remote or not e.def then return nil end
    if e.air or e.cat == "ship" then return nil end
    return e
  end
  local rp = RaycastParams.new()
  rp.FilterType = Enum.RaycastFilterType.Exclude
  G.ACT.wtScout = function(P, from, aim)
    if typeof(aim) ~= "Vector3" or typeof(from) ~= "Vector3" or aim.X ~= aim.X or from.X ~= from.X then return end
    local e = myVeh(P)
    if not e or not G.round or G.round.phase ~= "battle" then return end
    if not SCOUT_CAT[e.def.cat] then G.msg(P.pl, "bad", "wt.noScout") return end
    if (from - e.root.Position).Magnitude > 40 then from = e.root.Position + Vector3.new(0, (e.def.H or 6), 0) end
    local t = now()
    P.cd = P.cd or {}
    if t < (P.cd.wtScout or 0) then return end
    P.cd.wtScout = t + SC.cd
    local look = (aim - from)
    if look.Magnitude < 1 then return end
    look = look.Unit
    local cosC = math.cos(math.rad(SC.cone))
    local best, bestDot = nil, cosC
    for _, x in ipairs(G.ents) do
      if x.alive and x.team and x.team ~= P.team and x.root and (x.cat == "armor" or x.cat == "light") then
        local to = x.root.CFrame.Position - from
        local d = to.Magnitude
        if d > 4 and d < SC.range then
          local dot = to.Unit:Dot(look)
          if dot > bestDot then
            rp.FilterDescendantsInstances = { e.model, P.char }
            local hit = workspace:Raycast(from, to * 0.98, rp)
            local hitE = hit and G.entOf and G.entOf(hit.Instance)
            if not hit or hitE == x then best, bestDot = x, dot end
          end
        end
      end
    end
    if not best then G.msg(P.pl, "bad", "wt.scoutNone") return end
    if best.wtScoutT and t - best.wtScoutT < SC.relock then
      G.msg(P.pl, "bad", "wt.scoutAgain", math.ceil(SC.relock - (t - best.wtScoutT)))
      return
    end
    best.wtScoutT = t
    best.wtScout = { P = P, till = t + SC.time }
    if G.spotted and G.spotted[P.team] then G.spotted[P.team][best.id] = t + SC.time end
    G.addScore(P, Config.Score.spot or 15)
    G.msgTeam(P.team, "info", "wt.scouted", P.pl.DisplayName, { k = "veh." .. best.def.id })
  end

  ---------------------------------------------------------------- 火炮支援（战雷：坦克按键，准星下那块地延迟几秒落一轮炮弹，敌我都炸）
  --   防空车不能叫；冷却 cd 秒（侦察助攻多给一次，不用等冷却）；先落几发、再一阵覆盖，半径 r 格
  local AR = W.arty or { cd = 120, delay = 4, n = 12, r = 70, spread = 6, range = 11200,
    w = { id = "wtarty", dmg = 300, splash = 22, vs = { inf = 1, light = 1, armor = 0.6, air = 0, ship = 0.5, fort = 1.2 } } }
  local function artyReady(P)
    local t = now()
    return (P.wtArtyBonus or 0) > 0 or t >= (P.wtArtyT or 0)
  end
  local function pushArty(P)
    if not P.pl then return end
    local left = math.max(0, (P.wtArtyT or 0) - now())
    P.pl:SetAttribute("WtArtyCd", (left > 0 and (P.wtArtyBonus or 0) <= 0) and (workspace:GetServerTimeNow() + left) or nil)
    P.pl:SetAttribute("WtArtyBonus", (P.wtArtyBonus or 0) > 0 and P.wtArtyBonus or nil)
  end
  G.ACT.wtArty = function(P, aim)
    if typeof(aim) ~= "Vector3" or aim.X ~= aim.X then return end
    local e = myVeh(P)
    if not e or not G.round or G.round.phase ~= "battle" then return end
    if e.def.cat == "aa" then G.msg(P.pl, "bad", "wt.artyNo") return end
    local d = (Vector3.new(aim.X, 0, aim.Z) - Vector3.new(e.root.Position.X, 0, e.root.Position.Z)).Magnitude
    if d > AR.range then G.msg(P.pl, "bad", "wt.artyFar", math.floor(AR.range / 2.8)) return end
    if not artyReady(P) then G.msg(P.pl, "bad", "wt.artyCd", math.ceil((P.wtArtyT or 0) - now())) return end
    if (P.wtArtyBonus or 0) > 0 then P.wtArtyBonus -= 1 else P.wtArtyT = now() + AR.cd end
    pushArty(P)
    local Map = G.Map
    local x0, z0 = aim.X, aim.Z
    local src = { P = P, team = P.team, name = P.pl.DisplayName }
    G.msgTeam(P.team, "info", "wt.artyCalled", P.pl.DisplayName)
    G.fx({ k = "artyMark", p = Vector3.new(x0, Map.ground(x0, z0), z0), r = AR.r, t = AR.delay + AR.spread + 1, team = P.team })
    for i = 1, AR.n do
      task.delay(AR.delay - 1.2 + (i - 1) * AR.spread / AR.n, function()
        local a, r = math.random() * math.pi * 2, math.sqrt(math.random()) * AR.r
        local x, z = x0 + math.cos(a) * r, z0 + math.sin(a) * r
        G.shell(Vector3.new(x, Map.ground(x, z), z), AR.w, src, 1.2)
      end)
    end
  end

  ---------------------------------------------------------------- 车被打掉
  --   车主那一型记一笔「已毁」；打掉它的人记击毁地面 / 击落空中；侦察到的车被打掉，侦察的人有助攻；
  --   全服一条战雷式击杀信息（左边那一栏，客户端 WtBattle.lua）
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
    local sc = e.wtScout
    if sc and sc.P and sc.P ~= K and now() < sc.till and G.P[sc.P.pl] == sc.P then
      G.addScore(sc.P, SC.kill)
      sc.P.wtArtyBonus = math.min(2, (sc.P.wtArtyBonus or 0) + 1)
      pushArty(sc.P)
      G.msg(sc.P.pl, "good", "wt.scoutKill", { k = "veh." .. (e.def and e.def.id or "") })
    end
    if e.cat ~= "inf" and e.cat ~= "fort" and e.def and e.def.id then
      local D = e.driver or e.wtLastDriver
      local kname = (K and K.pl and K.pl.DisplayName) or (src and src.name) or nil
      local kveh = K and K.vehicle and K.vehicle.def and K.vehicle.def.id or (src and src.veh) or nil
      G.R.Drive:FireAllClients({ op = "wtFeed", k = kname, kt = src and src.team or nil, kv = kveh,
        v = D and D.pl and D.pl.DisplayName or nil, vt = e.team, vv = e.def.id, air = e.cat == "air" or nil, why = e.wtWhy,
        vid = D and D.pl and D.pl.UserId or nil })
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
