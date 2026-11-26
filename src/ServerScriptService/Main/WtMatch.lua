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
  -- 飞机、直升机（用户 11-25「第一辆必须是地面车，飞机要攒点数才能出」，同战雷）：准备阶段、第一辆都不免费，一直按价钱要 SP——
  --   开局 SP 是 0，所以得先开地面车打出分来（击毁、占点）攒够了才能出飞机
  local function isAir(vid, kind) return kind == "air" or AD.get(vid) ~= nil end
  G.wtIsAir = isAir
  -- 这辆车现在出要多少 SP（地面车：准备阶段、第一辆、PvE：0）
  function G.wtCost(P, vid, kind)
    if not on() then return 0 end
    local s = S(P)
    if isAir(vid, kind) then return Config.WtCost(vid, catOf(vid, kind), s.paid) end
    local R = G.round
    if not R or R.phase ~= "battle" then return 0 end
    if s.free then return 0 end
    return Config.WtCost(vid, catOf(vid, kind), s.paid)
  end
  -- 能不能出这辆：阵容满了、备用用完了、SP 不够都说一声
  -- 阵容按什么记：科技树出的车（Tech.lua 出车时设 P.wtKey）按科技树的键——借同一型号的两辆算两种；别的按型号
  local function keyOf(P, vid) return (P and P.wtKey) or vid end
  local function nameOf(P, vid) return (P and P.wtKey) and { k = "tree." .. P.wtKey } or { k = "veh." .. vid } end
  -- 为什么出不了（nil = 能出）：{ 语言键, 参数… }——出车时说一声（wtSpawnOk）
  local function whyNot(P, vid, kind)
    if not on() or not P or not P.pl or not vid then return nil end
    local s = S(P)
    local lk = keyOf(P, vid)
    local n = s.ln[lk] or 0
    if n == 0 and #s.order >= (W.lineup or 5) then return { "wt.lineupFull", W.lineup or 5 } end
    if n >= 1 + (W.backup or 1) then return { "wt.noBackup", nameOf(P, vid), n } end
    if isAir(vid, kind) and not s.ground then return { "wt.groundFirst" } end   -- 这一局还没出过地面车：飞机不让出
    local c = G.wtCost(P, vid, kind)
    if c > s.sp then return { "wt.needSp", c, math.floor(s.sp) } end
    return nil
  end
  function G.wtSpawnOk(P, vid, kind)
    local w = whyNot(P, vid, kind)
    if w then G.msg(P.pl, "bad", table.unpack(w)) return false end
    return true
  end
  local SKS = require(RS:WaitForChild("WtSkins"))
  -- 机库里选涂装、贴花（客户端 WtSkin.lua）：key 科技树的键，c 涂装、n 战术号码（0～999 或没有）、e 贴不贴国徽；这一局里记着
  function G.ACT.wtSkinSet(P, key, c, n, emb)
    if type(key) ~= "string" or #key > 40 then return end
    if type(c) ~= "string" or not SKS.CAMO[c] then c = "std" end
    n = tonumber(n)
    if n then n = math.clamp(math.floor(n), 0, 999) end
    P.wtSkin = P.wtSkin or {}
    P.wtSkin[key] = { c = (c ~= "std") and c or nil, n = n, e = emb == true }
  end
  function G.wtSpawned(P, vid, kind, e)
    if not P or not P.pl or not vid then return end
    -- ④ 配弹：按他在机库里配的再配一遍（等 Tech.lua 写完改装 e.wtFx、科技树的键 e.treeKey 再配）
    if e and G.wtAmmoInit then task.defer(function() pcall(G.wtAmmoInit, e, P) end) end
    -- ⑯ 涂装、贴花：他在机库里选的（G.ACT.wtSkinSet）写成车上的属性，客户端 View.lua 按它画
    if e then
      task.defer(function()
        if not e.model or not e.model.Parent then return end
        local key = e.treeKey or vid
        local sk = P.wtSkin and P.wtSkin[key]
        if not sk then return end
        e.model:SetAttribute("Camo", sk.c)
        e.model:SetAttribute("TacNo", sk.n)
        if sk.e then e.model:SetAttribute("Emb", SKS.natOf(e.treeKey, P.team)) end
      end)
    end
    local lk = keyOf(P, vid)
    if e then e.wtOwner, e.wtVid = P, lk end
    if not on() then return end
    local s = S(P)
    local c = G.wtCost(P, vid, kind)
    if (s.ln[lk] or 0) == 0 then table.insert(s.order, lk) end
    s.ln[lk] = (s.ln[lk] or 0) + 1
    local air = isAir(vid, kind)
    if G.round and G.round.phase == "battle" then
      if s.free and not air then s.free = false else s.paid += 1 end
      s.sp = math.max(0, s.sp - c)
    elseif air then   -- 准备阶段出飞机也要花 SP（地面车不花）
      s.sp = math.max(0, s.sp - c)
      s.paid += 1
    end
    if not air then s.ground = true end   -- 出过地面车了：以后能出飞机（SP 够的话）
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

  ---------------------------------------------------------------- 直接出击（战雷：阵亡以后在出击界面选车，人就在车里出生，不用走去召唤位）
  --   客户端 WtBattle.lua 的出击栏点一型 → { 型号, 装备 }：在自己主基地出生（地面车 base、飞机 baseAir），出生那一下挪到这一型的召唤位旁边、
  --   照召唤位那套出车（Depots spawnAt：SP、阵容、金币解锁、名额都照查），再挪到车边坐进去
  G.ACT.wtDeployVeh = function(P, vid, choice)
    if type(vid) ~= "string" or not P or not P.pl then return end
    local R = G.round
    if not R or (R.phase ~= "battle" and R.phase ~= "prep") or P.alive then return end
    local air = AD.get(vid)
    local gd = (not air) and VD.get(vid)
    if not air and not gd then return end
    local pads = {}
    for _, p in ipairs(G.pads or {}) do
      if p.team == P.team and p.summon and p.vids and table.find(p.vids, vid) and ((air and p.kind == "air") or (gd and p.kind == "veh")) then
        table.insert(pads, p)
      end
    end
    if #pads == 0 then G.msg(P.pl, "bad", "wt.noPad") return end
    if G.wtSpawnOk and not G.wtSpawnOk(P, vid, air and "air" or "veh") then return end
    P.spawnCF = nil
    G.ACT.deploy(P, (type(choice) == "table" or type(choice) == "string") and choice or (P.lastChoice or "rifle"), air and "baseAir" or "base")
    if not P.spawnCF then return end   -- 没部署成（出生点被占、兵力打光……：deploy 里已经说了）
    P.after = function(P2, char)
      local Map = G.Map
      for _, p in ipairs(pads) do
        local y = (G.airSurface and G.airSurface(p.term.X, p.term.Z)) or Map.ground(p.term.X, p.term.Z)
        char:PivotTo(CFrame.new(p.term.X + 1.5, y + 3, p.term.Z + 1.5))
        P2.padT = 0
        local e = G.padSpawnAt and G.padSpawnAt(P2, p, nil, vid)
        if e and e.root then
          task.wait(0.15)
          char:PivotTo(e.root.CFrame * CFrame.new((e.def.W or 8) / 2 + 3, 2, 0))
          task.wait(0.1)
          G.ACT.enterVeh(P2, e.id)
          return
        end
      end
      G.msg(P2.pl, "bad", "wt.padBusy")
    end
  end

  local AWARD = { first = 80, double = 60, triple = 120, rampage = 150, avenger = 60, marksman = 50 }   -- 奖章加多少分（也就攒 SP）
  -- 自己阵亡：连杀断了
  G.on("died", function(P)
    if P and P.wtm then P.wtm.streak = 0 end
  end)

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
    if K and K.pl and G.P[K.pl] == K and e.cat ~= "inf" and e.cat ~= "fort" and e.team ~= K.team and not e.noScore then   -- 试驾场的靶车不记击毁
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
    -- 战场奖章（战雷屏幕上方弹出来的那种）：首杀、双杀 / 三杀、坦克狂暴者（不死连杀 5 辆）、复仇者、神射手（1.5 公里外）
    if K and K.pl and G.P[K.pl] == K and e.cat ~= "inf" and e.cat ~= "fort" and e.team ~= K.team and not e.noScore then   -- 试驾场的靶车不发奖章（原来首杀奖章照发 80 分）
      local t = now()
      local s = S(K)
      local aw = {}
      local R = G.round
      if R and not R.wtFirst then R.wtFirst = true table.insert(aw, "first") end
      s.streak = (s.streak or 0) + 1
      s.kt = s.kt or {}
      table.insert(s.kt, t)
      while #s.kt > 0 and t - s.kt[1] > 12 do table.remove(s.kt, 1) end
      if #s.kt == 2 then table.insert(aw, "double") elseif #s.kt >= 3 then table.insert(aw, "triple") end
      if s.streak == 5 then table.insert(aw, "rampage") end
      local victim = e.driver or e.wtLastDriver
      for _, Q in pairs(G.P) do   -- 复仇者：打掉的这辆刚刚（20 秒内）击毁过我们队的人
        if Q.team == K.team and Q ~= K and Q.wtKilledBy == e and t - (Q.wtKilledT or 0) < 20 then table.insert(aw, "avenger") break end
      end
      local kp = K.vehicle and K.vehicle.root and K.vehicle.root.Position
      if kp and e.root and (kp - e.root.Position).Magnitude / 2.8 > 1500 then table.insert(aw, "marksman") end
      for _, a in ipairs(aw) do
        G.addScore(K, (AWARD[a] or 40))
        G.R.Drive:FireClient(K.pl, { op = "wtAward", a = a, pts = AWARD[a] or 40 })
      end
      if victim and victim.pl then victim.wtKilledBy, victim.wtKilledT = K.vehicle, t end
      -- 击毁奖励（用户 11-26「你自己设计一个击杀效果和音效以及奖励」）：金币当场发、研究点这一辆算多少（结算时一起发）、SP 这一下涨了多少；
      --   加成：弹药殉爆、一发击毁、越级击毁
      local KC = W.kill or {}
      local TT = require(RS:WaitForChild("TechTree"))
      local vit = e.treeKey and TT.byKey[e.treeKey]
      local kit = K.vehicle and K.vehicle.treeKey and TT.byKey[K.vehicle.treeKey]
      local mk = ((W.modeK or {})[G.wtModeNow and G.wtModeNow() or "rb"]) or 1
      local k, tags = 1, {}
      local B = KC.bonus or {}
      if e.wtWhy == "ammo" then k *= (B.ammo or 1.3) table.insert(tags, "ammo") end
      if e.wtHitsBy and e.wtHitsBy[K] == 1 then k *= (B.one or 1.25) table.insert(tags, "one") end
      if vit and kit and vit.br >= kit.br + (KC.brUp or 0.7) then k *= (B.up or 1.5) table.insert(tags, "up") end
      local rank = (vit and vit.rank) or 3
      local coins = math.floor(((KC.coin0 or 90) + rank * (KC.coinRank or 25)) * mk * k / 5 + 0.5) * 5
      local rp = math.floor((KC.rpKill or 250) * mk * k / 5 + 0.5) * 5
      if G.addCoins and coins > 0 then G.addCoins(K, coins) end
      K.wtKillRp = (K.wtKillRp or 0) + rp - math.floor((KC.rpKill or 250) * mk)   -- 加成那一截（基础的按击毁数结算时算）
      local R2 = G.round
      local sp = (R2 and R2.phase == "battle") and math.floor((Config.Score and Config.Score.vehicleKill or 0) * (W.perScore or 0.5)) or 0
      G.R.Drive:FireClient(K.pl, { op = "wtKillReward", vv = e.def and e.def.id or nil, vk = e.treeKey, sp = sp, coins = coins, rp = rp, tags = tags,
        air = e.cat == "air" or nil })
    end
    if e.cat ~= "inf" and e.cat ~= "fort" and e.def and e.def.id then
      local D = e.driver or e.wtLastDriver
      local kname = (K and K.pl and K.pl.DisplayName) or (src and src.name) or nil
      local kveh = K and K.vehicle and K.vehicle.def and K.vehicle.def.id or (src and src.veh) or nil
      -- kk / vk：科技树出的车（D 的 Tech.lua 记 e.treeKey）写科技树里的名字（借 M60A1 模型的 59 式写「59式中型坦克」）
      G.R.Drive:FireAllClients({ op = "wtFeed", k = kname, kt = src and src.team or nil, kv = kveh,
        kk = K and K.vehicle and K.vehicle.treeKey or nil, vk = e.treeKey,
        v = D and D.pl and D.pl.DisplayName or nil, vt = e.team, vv = e.def.id, air = e.cat == "air" or nil, why = e.wtWhy,
        vid = D and D.pl and D.pl.UserId or nil })
    end
  end)

  G.wtFeedOn = function() return on() end   -- Round.lua：开着战雷式击杀栏时，车毁那一下不再写老的击杀播报（免得一条写两遍）
  -- 纯载具对战（用户 11-25：「地图上还有不属于战雷的东西：电脑步兵还在、据点工事会自己开火、地雷 C4 望远镜还在——战雷陆战没有步兵，
  --   也没有会开火的电脑工事」）：战雷式对局开着、玩家不当步兵（Config.Wt.noInfantry）、不是 PvE、不是测试放行步兵（G.allowInfantry）时为真。
  --   Bots.lua 不刷电脑步兵、Forts.lua 工事不开火也不摆雷区、Weapons.lua 地雷 / C4 / 望远镜用不了（电脑开的车 AIVeh 照旧，战雷里也有）
  G.wtGroundOnly = function()
    return on() and (Config.Wt or {}).noInfantry == true and not G.pve and not G.allowInfantry
  end

  -- 推给自己的客户端（Round.lua personal）：SP、阵容（出过几次、毁了几次）、免费那一辆还在不在
  function G.wtPersonal(P)
    if not on() then return nil end
    local s = S(P)
    return { sp = math.floor(s.sp), free = s.free, paid = s.paid, order = s.order, ln = s.ln, lost = s.lost, ground = s.ground == true,
      max = W.lineup or 5, backup = W.backup or 1, earned = math.floor(s.earned), vk = s.vk, ak = s.ak }
  end
  -- 战况表、结算页的一行（Round.lua boardState）
  function G.wtBoard(P, row)
    local s = P.wtm
    if s and s.round == (G.round and G.round.n) then row.vk, row.ak, row.sp = s.vk, s.ak, math.floor(s.earned) end
  end

  ---------------------------------------------------------------- 敌人标记：历史 / 全真模式（用户 11-25「全部都做」①）
  --   战雷历史模式：屏幕上不标敌人，小地图上只有自己这队有人看得见的（视线没被地形、房子、烟幕挡住）和被侦察标记的才出来。
  --   每 0.5 秒（两队错开 0.25 秒）：对每辆敌方车 / 飞机 / 船 / 步兵，从离它最近的几个己方（真人、电脑车、机器人）各打一条线，
  --   只有地形、房子挡（实体、人都不挡）；看得见的、侦察标记着的实体号发给这一队（fx teamSeen），客户端小地图（Hud.lua）在 rb / sb 只画这些
  local SIGHT = { ground = 3600, air = 9000, inf = 1500, near = 4 }   -- 格：地面 3600（约 1.3 公里）、飞机 9000、步兵 1500；每个目标最多看 near 个己方
  local sightP = RaycastParams.new()
  sightP.FilterType = Enum.RaycastFilterType.Exclude
  sightP.IgnoreWater = true
  local VIEW_CAT = { armor = true, light = true, air = true, ship = true, inf = true }
  local function sightOf(team)
    local obs, tgts = {}, {}
    for _, Q in pairs(G.P) do
      if Q.team == team and Q.alive then
        local e = Q.vehicle
        local hrp = Q.char and Q.char:FindFirstChild("HumanoidRootPart")
        local p = (e and e.root and e.root.CFrame.Position) or (hrp and hrp.Position)
        if p then table.insert(obs, p + Vector3.new(0, 3, 0)) end
      end
    end
    for _, e in ipairs(G.ents) do
      if e.alive and e.root and VIEW_CAT[e.cat] and not e.testDummy then
        local p = e.root.CFrame.Position
        if e.team == team then
          if not e.driver then table.insert(obs, p + Vector3.new(0, 3, 0)) end   -- 有人开的车上面按真人算过了
        elseif e.team then
          table.insert(tgts, { e = e, p = p + Vector3.new(0, 1.5, 0) })
        end
      end
    end
    local ex = {}
    local ents = workspace:FindFirstChild("Ents")
    if ents then table.insert(ex, ents) end
    for _, pl in ipairs(game:GetService("Players"):GetPlayers()) do if pl.Character then table.insert(ex, pl.Character) end end
    sightP.FilterDescendantsInstances = ex
    local seen = {}
    for _, t in ipairs(tgts) do
      local R = t.e.air and SIGHT.air or ((t.e.cat == "inf") and SIGHT.inf or SIGHT.ground)
      local near = {}
      for _, o in ipairs(obs) do
        local d = (o - t.p).Magnitude
        if d < R then table.insert(near, { o = o, d = d }) end
      end
      table.sort(near, function(a, b) return a.d < b.d end)
      for i = 1, math.min(#near, SIGHT.near) do
        local o = near[i].o
        local hit = workspace:Raycast(o, t.p - o, sightP)
        if (not hit or (hit.Position - o).Magnitude > near[i].d - 4) and not (G.smokeBlocks and G.smokeBlocks(o, t.p)) then
          table.insert(seen, t.e.id)
          break
        end
      end
    end
    -- 侦察 / 望远镜标记着的（Weapons.lua 的 G.spotted，实体号做键的那些）
    local S = G.spotted and G.spotted[team]
    if S then
      local tt = now()
      -- 实体编号是 "e33" 这样的字符串（玩家是 "p<UserId>"，不算）：原来只认数字，被侦察 / 标记的车一直进不了这张单子
      for key, till in pairs(S) do
        if till > tt then
          if G.entById[key] then table.insert(seen, key)
          elseif type(key) ~= "string" then table.insert(seen, key)
          elseif tonumber(key) then table.insert(seen, tonumber(key)) end
        end
      end
    end
    return seen
  end
  task.spawn(function()
    local turn = 0
    while true do
      task.wait(0.25)
      turn += 1
      -- 历史 / 全真：小地图只画这些；街机也发（炮兵视角 ArtyView.lua 只画全队看得见的敌车，用户 11-25）
      if on() and G.round and (G.round.phase == "battle" or G.round.phase == "prep") then
        local team = (turn % 2 == 0) and "atk" or "def"
        local okS, seen = pcall(sightOf, team)
        if okS then
          for pl, Q in pairs(G.P) do
            if Q.team == team then G.R.Fx:FireClient(pl, { { k = "teamSeen", ids = seen } }) end
          end
        else
          warn("[战雷] 敌人标记出错：" .. tostring(seen))
        end
      end
    end
  end)
  G.wtSightOf = sightOf   -- 测试用

  ---------------------------------------------------------------- 标点、无线电（用户 11-25「全部都做」⑭，客户端 WtComms.lua）：发给同一队的人
  local RADIO = { need = true, follow = true, ok = true, no = true, retreat = true, enemy = true, attack = true, defend = true }
  local function toTeam(P, msg)
    for pl, Q in pairs(G.P) do
      if Q.team == P.team then G.R.Drive:FireClient(pl, msg) end
    end
  end
  local function okPos(p) return typeof(p) == "Vector3" and p.X == p.X and math.abs(p.X) < 1e6 and math.abs(p.Z) < 1e6 end
  function G.ACT.wtPing(P, pos)
    if not okPos(pos) then return end
    local t = now()
    if t < (P.pingT or 0) then return end
    P.pingT = t + 1.5
    toTeam(P, { op = "wtPing", p = pos, from = P.pl.DisplayName })
  end
  function G.ACT.wtRadio(P, k, arg, pos)
    if type(k) ~= "string" or not RADIO[k] then return end
    local t = now()
    if t < (P.radioT or 0) then return end
    P.radioT = t + 1.5
    if type(arg) ~= "string" or #arg > 6 then arg = nil end
    toTeam(P, { op = "wtRadio", k = k, arg = arg, p = okPos(pos) and pos or nil, from = P.pl.DisplayName })
  end

  ---------------------------------------------------------------- 匹配（用户 11-26：「点开战先匹配，匹配一分钟后人不够就补人机，两边的人机的车辆要符合我匹配时带的
  --   最高权重的载具，跟战雷一样，人机的分数也要出现在记分板」）
  --   一局打完回机库，下一局先是「匹配中」（Round.lua 的 queue 阶段：世界照旧在，机库、试驾照常用）：
  --   有人点「开战」（ACT.matchJoin，带着选中的那一辆）就起算 Config.Match.wait 秒；到点、或者真人凑满两队（2 × Wt.teamSize）就开这一局（准备阶段）——
  --   点过开战的人自动坐进点的那一辆出现在自己基地；没点的照旧在机库，打起来以后再点「加入战斗」直接进（Tech.lua deployVeh：顶替电脑，电脑车被毁后不再补）。
  --   这一局真打的人记 P.match = 局号：AIVeh.lua 按每队真打的人数补电脑车（补到 teamSize），Tech.lua 的本局战斗等级只看匹配进来的人的阵容（阵容里最高的那辆）
  local MC = Config.Match or {}
  function G.matchOn() return MC.on ~= false and on() and not G.matchOff and not G.allowInfantry end
  local function queuedList()
    local out = {}
    for _, P in pairs(G.P) do
      if P.queued and P.pl and P.pl.Parent then table.insert(out, P) end
    end
    return out
  end
  G.matchQueued = queuedList   -- 测试用
  local function full() return 2 * (W.teamSize or 8) end
  -- 发给客户端（Round.lua common）：排了几个人、还剩几秒（第一个人点了开战才起算）
  function G.queueState()
    local R = G.round
    if not R or R.phase ~= "queue" then return nil end
    return { n = #queuedList(), need = full(), left = R.queueEnds and math.max(0, math.ceil(R.queueEnds - now())) or nil, wait = MC.wait or 60 }
  end
  -- 进局（这一局算他的）：客户端机库变成局内选车页（Round.lua 推 C.pick），先把自己基地一带的地图传过来（开着 streaming 时，选车的这几秒里出生点一带都到位）
  local function enterMatch(P)
    local R = G.round
    P.match = R and R.n or nil
    P.pickT = os.clock()
    local pad = G.treePadFor and G.treePadFor(P.team, false, false)   -- 本队地面车的出车位（Tech.lua）
    local base = pad and pad.term
    if typeof(base) == "Vector3" and P.pl and P.pl.Parent then
      task.spawn(function() pcall(function() P.pl:RequestStreamAroundAsync(base, 30) end) end)
    end
    G.pushOne(P)
  end
  G.wtEnterMatch = enterMatch
  G.ACT.matchJoin = function(P, key)
    local R = G.round
    if not R or type(key) ~= "string" then return end
    if R.phase ~= "queue" then   -- 已经在打（准备 / 战斗）：进局、出选车界面（同战雷：「加入战斗」以后在局里选车）
      if P.testDeploy then if G.ACT.deployVeh then G.ACT.deployVeh(P, key) end return end
      if G.treeCanQueue and not G.treeCanQueue(P, key) then return end
      P.pickPref = key
      enterMatch(P)
      return
    end
    if G.treeCanQueue and not G.treeCanQueue(P, key) then return end   -- 阵容里没有、没买、超出战斗等级（Tech.lua 自己说原因）
    P.queued = key
    if not R.queueEnds then R.queueEnds = now() + (MC.wait or 60) end
    G.pushAll()
  end
  G.ACT.matchCancel = function(P)
    if not P.queued then return end
    P.queued = nil
    G.pushAll()
  end
  -- 局内选车页（机库）上的「退出战斗」：这一局不打了（车没了才能退；坐在车里的不理）
  G.ACT.matchLeave = function(P)
    if P.vehicle then return end
    P.match, P.pickPref = nil, nil
    G.pushOne(P)
  end
  -- 匹配够了没有（Round.lua 每步问）：没人排了就停表（下一个人点了重新起算）
  function G.queueStep(t)
    local R = G.round
    local n = #queuedList()
    if n == 0 then R.queueEnds = nil return false end
    if n >= full() then return true end
    return R.queueEnds ~= nil and t >= R.queueEnds
  end
  -- 匹配到了：排着的人都算这一局的，进局先出选车界面（用户 11-26「匹配完之后 两边再开始在局内有一个界面选择载具」；
  --   原来直接坐进机库里点的那一辆）——机库里点的那一辆在界面上先选中（pickPref）；人机照旧自己出车（AIVeh.lua）
  G.on("matchFound", function()
    for _, P in ipairs(queuedList()) do
      local key = P.queued
      P.queued = nil
      P.pickPref = key
      enterMatch(P)
    end
    if G.treeRoundBr then pcall(G.treeRoundBr) end
    -- 不再在屏幕正中写「匹配完成：进入战斗（人不够的位置由人机补上）」（用户 11-26「把那串字去掉太难看」）：机库的主按钮变成「出击」就说明了
  end)
  G.on("left", function(P) P.queued = nil end)
  -- 这一队这一局真打的人（匹配进来的、半路加入的；坐在车里的、活着的也算）——电脑补到 teamSize 时扣掉他们（AIVeh.lua）
  function G.matchPlayers(team)
    local R = G.round
    local n = 0
    for _, Q in pairs(G.P) do
      if Q.team == team and Q.pl and Q.pl.Parent and ((R and Q.match == R.n) or Q.vehicle or Q.alive) then n += 1 end
    end
    return n
  end
end

return WtMatch
