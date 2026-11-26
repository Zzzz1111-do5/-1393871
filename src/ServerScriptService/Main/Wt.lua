-- Roblox全面大战场——战雷式的车辆伤害（服务器；用户 11-24「把整个游戏做成战雷」，四项全勾：乘员和模块伤害 + X 光回放也要）
--   规则在 ReplicatedStorage/WtDamage.lua（装甲毫米、穿深、车里的乘员和模块摆在哪）；这里按它算：
--   · 炮弹打中车（Ents.lua stepShots）：按打中的面、入射角、弱点算等效厚度，和这一发的穿深比——跳弹 / 未击穿 / 击穿
--     击穿：弹芯 / 金属射流顺着弹道往里钻（打到的乘员、模块重伤），再一锥破片（每片伤第一个碰到的）；杀爆弹打穿了在里面炸一团
--   · 火箭弹、导弹直接命中按破甲弹算；别的爆炸（炮弹、炸弹、地雷、溅射）按离车多近伤车外的履带、炮管，太近、太大才伤里面
--   · 乘员各自有血：驾驶员没了开不动、炮长没了打不了炮、装填手没了装填慢；关键位空了几秒后别的乘员顶上去（照战雷）
--   · 模块：发动机 / 传动 / 履带坏了动不了，炮管 / 炮闩坏了打不了，炮塔驱动坏了转得慢；发动机、油箱中弹会起火（烧乘员），
--     弹药架中弹会殉爆（东方坦克的转盘一炸就掀炮塔；M1 的炮塔尾舱有泄压板：弹炸了、人没事）
--   · 车被击毁：乘员剩不到一半、或者殉爆；原来的血量（e.hp）只跟着乘员算个比例给界面看
--   · 车里的人能按键维修（坏的模块修到能用，十几秒）、灭火（灭火器有冷却）——客户端 WtHud / Drive 发 ACT.wtFix / ACT.wtExt
--   给开炮的人发 { op = "wtHit" }（命中提示 + X 光回放），给车里的人发 { op = "wtHurt" }（车组 / 模块面板闪一下）
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Wt = {}

function Wt.init(G)
  local W = require(RS:WaitForChild("WtDamage"))
  local Config = G.Config
  local V = Vector3.new
  local CF = CFrame.new
  local now = os.clock
  local M = W.M
  local CREW_DMG = { core = 160, spall = 46, blast = 90 }
  local MOD_DMG = { core = 130, spall = 34, blast = 70 }
  local REPLACE_T = 6     -- 关键位空了多少秒后别人顶上
  local FIX_T = 12        -- 维修要几秒
  -- 科技树改装（WtMods，Tech.lua 出车时写的 e.wtFx）：工具箱修得快；没研究零件 / 灭火器修不了 / 灭不了
  local function fixTime(e) return FIX_T * ((e.wtFx and e.wtFx.repK) or 1) end
  local EXT_CD = 20       -- 灭火器冷却

  local function baseOf(e) return e.root.CFrame * CF(0, -e.def.H / 2, 0) end

  ---------------------------------------------------------------- 建车时：每个乘员、模块一份血

  function G.wtSetup(e)
    local d = e.def
    if not d or not (d.cat == "tank" or d.cat == "apc" or d.cat == "aa" or d.cat == "arty") then return end
    local lay = W.layout(d)
    local S = { crew = {}, mods = {}, byK = {}, fireT = nil, fixT = nil, extT = 0, seat = {} }
    for _, it in ipairs(lay.list) do
      local c = { it = it, hp = it.hp, max = it.hp }
      if it.kind == "crew" then
        c.role, c.seat = it.role, it.role
        table.insert(S.crew, c)
        S.seat[it.role] = c
      else
        table.insert(S.mods, c)
      end
      S.byK[it.k] = c
    end
    S.total = #S.crew
    e.wt = S
    e.wtMaxHp = e.hp
    G.wtPush(e)
  end

  -- 模块的状态：2 好、1 坏了（还能凑合）、0 毁了
  local function modState(c)
    if c.hp <= 0 then return 0 end
    return (c.hp < c.max * 0.55) and 1 or 2
  end
  local function crewState(c)
    if c.hp <= 0 then return 0 end
    return (c.hp < 55) and 1 or 2
  end
  local function alive(S)
    local n = 0
    for _, c in ipairs(S.crew) do if c.hp > 0 then n += 1 end end
    return n
  end
  local function seatOk(S, role)
    local c = S.seat[role]
    return c ~= nil and c.hp > 0
  end
  local function ok(S, k) local c = S.byK[k] return c == nil or c.hp > 0 end

  -- 能不能开、能不能打主炮、炮塔转多快、装填慢多少
  local function effects(e)
    local S = e.wt
    local mob = seatOk(S, "drv") and ok(S, "engine") and ok(S, "trans") and ok(S, "trackL") and ok(S, "trackR")
    local gun = seatOk(S, "gnr") and ok(S, "breech") and ok(S, "barrel")
    if not S.seat.gnr then gun = ok(S, "breech") and ok(S, "barrel") and alive(S) > 0 end   -- 没有炮长位的车（轻型车）：剩人就能打
    local trav = 1
    local td = S.byK.tdrive
    if td then trav = (td.hp <= 0) and 0.25 or ((modState(td) == 1) and 0.6 or 1) end
    if not seatOk(S, "gnr") and S.seat.gnr then trav = math.min(trav, 0.5) end
    local rel = 1
    if S.seat.ldr and not seatOk(S, "ldr") then rel = 1.6 end   -- 装填手没了：别人凑合装填
    if S.fixT then gun = false end                              -- 修车的时候不能开炮
    S.mob, S.gun, S.trav, S.rel = mob, gun, trav, rel
  end

  -- 状态写成属性（客户端：左下车组 / 模块面板、开不了车、打不了炮、炮塔转得慢）
  function G.wtPush(e)
    local S = e.wt
    if not S or not e.model then return end
    effects(e)
    local cs = {}
    for _, c in ipairs(S.crew) do table.insert(cs, crewState(c) .. c.seat) end
    local ms = {}
    for _, c in ipairs(S.mods) do table.insert(ms, tostring(modState(c))) end
    local m = e.model
    m:SetAttribute("WtC", table.concat(cs, ","))
    m:SetAttribute("WtM", table.concat(ms))
    m:SetAttribute("WtF", S.fireT ~= nil)
    m:SetAttribute("WtAF", S.ammoFireT ~= nil)   -- 弹药架起火（客户端 WtVfx：舱口喷火）
    m:SetAttribute("WtMob", S.mob)
    m:SetAttribute("WtGun", S.gun)
    m:SetAttribute("WtTrav", S.trav)
    m:SetAttribute("WtFix", S.fixT and math.clamp((now() - S.fixT) / fixTime(e), 0, 1) or nil)
    -- 原来的血量（界面上的血条、名牌）：按活着的乘员算个比例
    if e.alive and e.wtMaxHp then
      e.hp = math.max(1, e.wtMaxHp * alive(S) / math.max(1, S.total))
      m:SetAttribute("Hp", math.floor(e.hp))
    end
  end
  G.wtCanMove = function(e) return not e.wt or e.wt.mob ~= false end
  -- 观瞄（11-26）：电脑开的车观瞄受损 / 打坏了打得不准、发现得慢——返回散布倍数（1 好、1.8 受损、3 打坏）
  G.wtOptK = function(e)
    local c = e and e.wt and e.wt.byK.optics
    if not c then return 1 end
    local s = modState(c)
    return (s == 0) and 3 or ((s == 1) and 1.8 or 1)
  end
  G.wtCanFire = function(e, wid)
    local S = e.wt
    if not S then return true end
    local VD = require(RS:WaitForChild("VehDefs"))
    local w = VD.W[wid]
    if w and (w.kind == "shell" or w.kind == "arty" or w.kind == "sam" or w.kind == "atgm") then return S.gun ~= false end
    return alive(S) > 0 and not S.fixT
  end
  G.wtReloadK = function(e) return (e.wt and e.wt.rel) or 1 end

  ---------------------------------------------------------------- 伤、死、毁

  local function msgTo(e, payload)
    for _, P in ipairs({ e.driver, table.unpack(e.pass or {}) }) do
      if P and P.pl then G.R.Drive:FireClient(P.pl, payload) end
    end
  end

  local function destroy(e, src, why)
    if not e.alive then return end
    e.wtWhy = why
    e.model:SetAttribute("WtWhy", why)   -- 客户端 View：殉爆才掀炮塔
    local base = baseOf(e)
    if why == "ammo" then   -- 殉爆：一大团火（客户端 View / WreckFx 画残骸，这里多一声大的）
      local tp = e.def.turret and e.def.turret.pivot or V(0, e.def.hullH or 4, 0)
      local at = (base * CF(tp)).Position
      if W.CAROUSEL[e.def.id] and e.def.turret then   -- 弹在车体底下的：先烧几秒再炸、炮塔飞起来（客户端按 WtCook 同步）
        local cook = W.cookSecs(e.id)
        e.model:SetAttribute("WtCook", cook)
        task.delay(cook, function() G.fx({ k = "boom", p = at, s = 4.6, c = "wreck" }) end)
      else
        G.fx({ k = "boom", p = at, s = 4.2, c = "wreck" })
      end
    end
    e.wtLastDriver = e.driver   -- 车毁了以后车里的人就下车了：击杀信息、「你被击毁」那一发的 X 光要发给他们
    e.wtLastPass = e.pass and table.clone(e.pass) or nil
    G.wtRaw = true
    G.damageEnt(e, 1e9, src)
    G.wtRaw = false
  end

  -- 一个零件挨了 amt：返回 这一下有没有变状态（乘员：重伤 / 阵亡；模块：坏 / 毁）
  local function hurt(e, c, amt, out, src)
    if not c or c.hp <= 0 then return end
    local s0 = (c.it.kind == "crew") and crewState(c) or modState(c)
    c.hp = math.max(0, c.hp - amt)
    local s1 = (c.it.kind == "crew") and crewState(c) or modState(c)
    if s1 ~= s0 then table.insert(out, { k = c.it.k, kind = c.it.kind, s = s1, seat = c.seat }) end
    if c.it.troop and e.pass and #e.pass > 0 then   -- 打进载员舱：伤里面坐着的人
      local Q = e.pass[math.random(1, #e.pass)]
      if Q and Q.char then G.hurtChar(Q.char, amt * 0.9, src) end
    end
  end

  -- 关键位空了：过几秒别人顶上（炮长位：装填手 → 车长；驾驶员位：车长 → 装填手；驾驶员、炮长之间不互换，免得来回换）
  local ORDER = { gnr = { "ldr", "cmd" }, drv = { "cmd", "ldr" } }
  local function scheduleSwap(e)
    local S = e.wt
    for role, from in pairs(ORDER) do
      if S.seat[role] and S.seat[role].hp <= 0 and not S.swap then
        for _, r2 in ipairs(from) do
          local c = S.seat[r2]
          if c and c.hp > 0 then
            S.swap = { role = role, from = r2, t = now() + REPLACE_T }
            msgTo(e, { op = "wtSwap", role = role, from = r2, t = REPLACE_T })
            break
          end
        end
      end
    end
  end

  -- 泄压板（M1 炮塔尾舱）：弹炸 / 烧起来都从炮塔顶上的泄压板往上泄——一道几米高的火柱烧六七秒（客户端 WtVfx 看属性 WtBlow），
  --   乘员没事，尾舱的弹没了（只剩车体里的两成）
  local function blowout(e, c, res)
    c.hp = 0
    res.blow = true
    G.fx({ k = "boom", p = res.wp or e.root.CFrame.Position, s = 2.0, c = "shell" })
    e.wtBlowN = (e.wtBlowN or 0) + 1
    e.model:SetAttribute("WtBlow", e.wtBlowN)
    local VD = require(RS:WaitForChild("VehDefs"))
    for wid, st in pairs(e.wst or {}) do
      local w = VD.W[wid]
      if w and w.kind == "shell" then st.reserve = math.floor(st.reserve * 0.2) end
    end
  end

  -- 这一下伤完以后：殉爆、乘员不够、起火
  local function after(e, src, res, flags)
    local S = e.wt
    if flags.ammo then
      local c = S.byK.ammo
      if c and c.it.blow and flags.ammoK == "ammo" then   -- M1 炮塔尾舱的弹：泄压板往上泄，人没事，尾舱的弹没了、烧一阵
        blowout(e, c, res)
      else
        res.kill, res.why = true, "ammo"
        destroy(e, src, "ammo")
        return
      end
    end
    if alive(S) * 2 < S.total or alive(S) == 0 then
      res.kill, res.why = true, "crew"
      destroy(e, src, "crew")
      return
    end
    -- 弹药架起火（11-26「弹药舱燃烧」）：发射药烧起来——带泄压板的尾舱照旧往上泄（人没事、这一架弹没了）；
    --   别的：舱口往外喷火七到十秒（比普通起火凶：烧乘员快），烧完没灭（Y 灭火器）有四成会殉爆
    if flags.ammoFire and not flags.ammo then
      local c = S.byK[flags.ammoFire]
      if c and c.it.blow then
        blowout(e, c, res)
      else
        local t = now()
        S.fireT = S.fireT or t
        S.ammoFireT = t
        S.fireUntil = math.max(S.fireUntil or 0, t + 7 + math.random() * 3)
        res.fire, res.ammoFire = true, true
      end
    end
    if flags.fire and not S.fireT then
      S.fireT = now()
      S.fireUntil = now() + 10 + math.random() * 14
      res.fire = true
    end
    scheduleSwap(e)
    G.wtPush(e)
  end

  -- 击穿以后：弹芯 / 射流 + 一锥破片；HE 在里面炸。p、dir 底座系
  local function inside(e, a, p, dir, resid, out, flags, src, seed)
    local d, S = e.def, e.wt
    local yaw = e.ty or 0
    local hitAmmo = function(c, k)
      if c.it.k == "ammo" or c.it.k == "ammoH" then
        local VD = require(RS:WaitForChild("VehDefs"))
        local left, full = 0, 0
        for wid, st in pairs(e.wst or {}) do
          local w = VD.W[wid]
          if w and w.kind == "shell" then left += st.mag + st.reserve full += (w.mag or 1) + (w.reserve0 or w.reserve or 30) end
        end
        local frac = (full > 0) and math.clamp(left / full, 0.15, 1) or 1   -- 带的弹越少越不容易殉爆（战雷的「少带弹」）
        local rl, rf = nil, nil
        if G.wtRackLeft then rl, rf = G.wtRackLeft(e, c.it.k) end   -- ④ 这一块弹架（待发 / 车体）现在有几发：空了打中也不炸
        if rl then frac = (rl <= 0) and 0 or math.clamp(rl / rf, 0.15, 1) end
        if math.random() < k * frac then flags.ammo, flags.ammoK = true, c.it.k
        elseif frac > 0 and math.random() < k * frac * 0.9 then flags.ammoFire = flags.ammoFire or c.it.k end   -- 没炸：发射药烧起来（弹药架起火，11-26）
      end
      if (c.it.k == "engine" and math.random() < 0.28 * (k / 0.5)) or ((c.it.k == "fuelL" or c.it.k == "fuelR") and math.random() < 0.4 * (k / 0.5)) then
        flags.fire = true
      end
    end
    local o = p + dir * 0.1
    local coreLen = (a.core or 0) * M * math.clamp(0.55 + resid / 350, 0.55, 1.5)
    local paths = { core = {}, spall = {} }
    if coreLen > 0 then
      local hits = W.trace(d, yaw, o, dir, coreLen, true)
      for _, h in ipairs(hits) do
        local c = S.byK[h.it.k]
        hurt(e, c, (h.it.kind == "crew") and CREW_DMG.core or MOD_DMG.core, out, src)
        hitAmmo(c, 0.7)
      end
      paths.core = { coreLen }
    end
    if (a.n or 0) > 0 then
      local rays = W.cone(dir, a.spall or 18, a.n, seed)
      for i, rv in ipairs(rays) do
        local len = (1.4 + (i % 4) * 0.35) * M
        local hits = W.trace(d, yaw, o, rv, len, true)
        local h = hits[1]
        if h then
          local c = S.byK[h.it.k]
          hurt(e, c, (h.it.kind == "crew") and CREW_DMG.spall or MOD_DMG.spall, out, src)
          hitAmmo(c, 0.22)
          if hits[2] and math.random() < 0.35 then   -- 有的破片穿过第一个还能伤后面一个
            local c2 = S.byK[hits[2].it.k]
            hurt(e, c2, ((hits[2].it.kind == "crew") and CREW_DMG.spall or MOD_DMG.spall) * 0.5, out, src)
          end
        end
      end
    end
    if a.blast and a.t == "he" then   -- 杀爆弹打穿了在里面炸：一团里的都伤
      local R = a.blast * M * 0.6
      local c0 = o + dir * 0.8 * M
      for _, c in ipairs(S.crew) do
        local dd = (W.center(d, yaw, c.it) - c0).Magnitude
        if dd < R then hurt(e, c, CREW_DMG.blast * (1 - 0.6 * dd / R), out, src) end
      end
      for _, c in ipairs(S.mods) do
        local dd = (W.center(d, yaw, c.it) - c0).Magnitude
        if dd < R then hurt(e, c, MOD_DMG.blast * (1 - 0.6 * dd / R), out, src) hitAmmo(c, 0.5) end
      end
    end
  end

  -- 车外的零件（履带、炮管）：没击穿也能打坏——打中的点在它盒子里（稍放宽）
  local function external(e, p, amt, out, src)
    local d, S = e.def, e.wt
    for _, c in ipairs(S.mods) do
      if c.it.ext and W.inside(d, e.ty or 0, p, c.it, 0.6) then hurt(e, c, amt, out, src) end
    end
  end

  local function sendHit(e, s, res, out, extra)
    local P = s.src and s.src.P
    if P then   -- 谁打中过它几发（WtMatch.lua 击毁奖励的「一发击毁」）
      e.wtHitsBy = e.wtHitsBy or {}
      e.wtHitsBy[P] = (e.wtHitsBy[P] or 0) + 1
    end
    local payload = { op = "wtHit", id = e.id, veh = e.def.id, r = res.r, kill = res.kill, why = res.why, fire = res.fire, blow = res.blow,
      parts = out, pen = res.pen and math.floor(res.pen) or nil, arm = res.eff and math.floor(res.eff) or nil, ang = res.ang and math.floor(res.ang) or nil,
      dist = res.dist and math.floor(res.dist) or nil, xr = extra, tk = e.treeKey }   -- tk：科技树出的车（界面写科技树里的名字）
    if P and P.pl and G.P[P.pl] == P then G.R.Drive:FireClient(P.pl, payload) end
    if not res.kill then
      msgTo(e, { op = "wtHurt", r = res.r, parts = out, fire = res.fire, from = s.src and s.src.name, xr = extra })
    else   -- 被击毁的那一发：车里的人看「被 XX 的 YY 击毁」和这一发的 X 光（战雷的击毁回放）
      local kveh = P and P.vehicle and P.vehicle.def and P.vehicle.def.id or nil
      local kill = table.clone(payload)
      kill.op, kill.from, kill.kveh = "wtKilled", (P and P.pl and P.pl.DisplayName) or (s.src and s.src.name), kveh
      kill.kk = P and P.vehicle and P.vehicle.treeKey or nil
      kill.kid = (P and P.vehicle and P.vehicle.id) or s.byEnt or nil   -- 击杀镜头（⑮，DeathFx.lua）看这辆
      for _, Q in ipairs({ e.wtLastDriver or e.driver, table.unpack(e.wtLastPass or e.pass or {}) }) do
        if Q and Q.pl then G.R.Drive:FireClient(Q.pl, kill) end
      end
    end
    G.wtHits = (G.wtHits or 0) + 1   -- 测试用
    G.wtLast = payload
  end

  -- 弹孔（用户 11-25「全部都做」⑨）：客户端 View.lua 在命中点贴一个焦黑的孔（击穿）/ 灰坑（没击穿）/ 擦痕（跳弹），跟着车体 / 炮塔走
  --   坐标按车自己的：车体上的按底座系，炮塔上的按炮塔系（W.toTur）——特效晚到零点几秒，车开着也贴得准
  local function hole(e, res, vel, r, zone)
    local n = res.Normal
    if typeof(n) ~= "Vector3" or n.Magnitude < 0.1 then n = -vel end
    local base = baseOf(e)
    local lp, ln, ld = base:PointToObjectSpace(res.Position), base:VectorToObjectSpace(n), base:VectorToObjectSpace(vel)
    local tur = zone == "tur" and e.def.turret ~= nil
    if tur then
      local yaw = e.ty or 0
      lp, ln, ld = W.toTur(e.def, lp, yaw), W.toTurDir(ln, yaw), W.toTurDir(ld, yaw)
    end
    local function a3(v3) return { math.floor(v3.X * 100) / 100, math.floor(v3.Y * 100) / 100, math.floor(v3.Z * 100) / 100 } end
    G.fx({ k = "wtHole", id = e.id, lp = a3(lp), ln = a3(ln), ld = a3(ld), r = r, z = tur or nil })
  end

  -- 炮弹、火箭弹、导弹直接打在车上：返回 "ric"（调用方按原来那套弹开）、true（这一发管完了，别再按血量扣）、nil（不是这套管的车）
  function G.wtShellHit(e, s, res)
    local S = e and e.wt
    if not S or not e.alive or not res then return nil end
    local d = e.def
    local base = baseOf(e)
    local p = base:PointToObjectSpace(res.Position)
    local vel = s.vel.Magnitude > 1e-3 and s.vel.Unit or (e.root.CFrame.Position - res.Position).Unit
    local dir = base:VectorToObjectSpace(vel)
    local yaw = e.ty or 0
    local distM = ((s.p0 or res.Position) - res.Position).Magnitude / M
    local pen, a = W.pen(s.w, distM)
    local zone, face, weak, n, _, dq = W.where(d, p, dir, yaw)
    local ang = math.deg(math.acos(math.clamp(-dq:Dot(n), -1, 1)))
    local mm = W.armor(d, zone, face, a.t) * weak
    local eff = W.effective(mm, ang, a.t)
    local ek = (s.kind == "shell") and G.eraShell and G.eraShell(e, s, res.Position)   -- 爆反挡了这一发（Era.lua 已经引爆了那块）
    if not ek and s.kind ~= "shell" and G.eraBlast then   -- 火箭弹、导弹：顺着来向找爆反块
      local m = G.eraBlast(res.Position, s.w, s.vel)
      ek = m and m[e] or nil
    end
    if ek then pen = pen * ((a.t == "ce" and a.tandem) and math.max(ek, 0.85) or ek) end
    local rr = { dist = distM, pen = pen, eff = eff, ang = ang }
    local out = {}
    local seed = math.floor((res.Position.X * 13 + res.Position.Z * 7 + now() * 97) % 100000) + 1
    local xr = { p = { p.X, p.Y, p.Z }, d = { dir.X, dir.Y, dir.Z }, ty = yaw, seed = seed, half = a.spall or 18, n = a.n or 0,
      core = 0, zone = zone, face = face }
    local rp = W.ricochet(a.t, ang)
    if rp > 0 and math.random() < rp then
      hole(e, res, vel, a.t == "ce" and "np" or "ric", zone)
      if a.t == "ce" then   -- 破甲弹太斜：引信不发火 / 射流打不进
        rr.r = "np"
        external(e, p, 30, out, s.src)
        sendHit(e, s, rr, out, xr)
        after(e, s.src, rr, {})
        return true
      end
      rr.r = "ric"
      sendHit(e, s, rr, out, xr)
      return "ric"
    end
    if pen < eff then
      rr.r = "np"
      hole(e, res, vel, "np", zone)
      external(e, p, (a.t == "he") and 60 or 45, out, s.src)
      if a.t == "he" and a.blast then   -- 杀爆弹没打穿：冲击波伤车外的零件，装甲很薄时也震伤里面的人
        for _, c in ipairs(S.mods) do
          if c.it.ext and (W.center(d, yaw, c.it) - p).Magnitude < a.blast * M then hurt(e, c, 40, out, s.src) end
        end
        if mm < 20 then for _, c in ipairs(S.crew) do if (W.center(d, yaw, c.it) - p).Magnitude < a.blast * M * 0.5 then hurt(e, c, 35, out, s.src) end end end
      end
      local flags = {}
      if a.t == "ce" then   -- 破甲 / 射流弹没打穿：射流钻进装甲里一小截就没劲了（客户端画一小段亮光、一团火花）
        G.fx({ k = "wtJet", p = res.Position, d = vel, len = 0.5 * M, pen = false, big = a.jet or nil })
      end
      sendHit(e, s, rr, out, xr)
      after(e, s.src, rr, flags)
      return true
    end
    rr.r = "pen"
    hole(e, res, vel, "pen", zone)
    external(e, p, 60, out, s.src)
    local flags = {}
    inside(e, a, p, dir, pen - eff, out, flags, s.src, seed)
    xr.core = (a.core or 0) * math.clamp(0.55 + (pen - eff) / 350, 0.55, 1.5)
    if a.t == "ce" then   -- 金属射流：从命中点顺着来向钻进车里（客户端 WtHud 画一道白热的射流、一圈火花；X 光里画成亮青白线）
      xr.jet = true
      xr.big = a.jet or nil   -- 专门的金属射流弹：X 光动画里射流更粗、熔珠更多
      G.fx({ k = "wtJet", p = res.Position, d = vel, len = xr.core * M, pen = true, big = a.jet or nil })
    end
    rr.wp = res.Position
    after(e, s.src, rr, flags)
    sendHit(e, s, rr, out, xr)
    return true
  end

  -- 别的伤害（炸弹、炮弹落在旁边、地雷、溅射、航炮扫射……）：Ents.lua damageEnt 交到这里，不直接扣血。
  --   按这一下占这类车满血的几成（frac）分到车外的零件（履带、炮管）和里面（乘员、发动机），够大就整车完
  function G.wtGeneric(e, amt, src, pos)
    local S = e.wt
    if not S or not e.alive or amt <= 0 then return end
    local cat = Config.VehicleCats[e.def.cat]
    local frac = amt / math.max(1, (cat and cat.hp) or 1000)
    if frac < 0.015 then return end
    local out = {}
    local d = e.def
    local yaw = e.ty or 0
    local p = pos and baseOf(e):PointToObjectSpace(pos) or nil
    -- 车外：离炸点近的履带、炮管
    for _, c in ipairs(S.mods) do
      if c.it.ext then
        local near = p and (W.center(d, yaw, c.it) - p).Magnitude < 4 * M or (not p and math.random() < 0.5)
        if near then hurt(e, c, 220 * frac, out, src) end
      end
    end
    -- 里面：薄皮车按比例伤，重装甲车只有很大的一下（frac 过半）才震伤里面
    local P0 = W.prof(d)
    local roof = (P0.hull.t and P0.hull.t[1]) or 20
    local inK = (roof < 25) and 1 or math.clamp((frac - 0.35) * 1.6, 0, 1)
    if inK > 0 then
      local flags = {}
      for _, c in ipairs(S.crew) do if math.random() < 0.6 then hurt(e, c, 160 * frac * inK, out, src) end end
      for _, c in ipairs(S.mods) do
        if not c.it.ext and math.random() < 0.5 then
          hurt(e, c, 180 * frac * inK, out, src)
          if (c.it.k == "ammo" or c.it.k == "ammoH") and math.random() < 0.25 * inK then flags.ammo, flags.ammoK = true, c.it.k end
          if c.it.k == "engine" and math.random() < 0.2 * inK then flags.fire = true end
        end
      end
      local rr = { r = "pen" }
      after(e, src, rr, flags)
      if #out > 0 then
        if not rr.kill then msgTo(e, { op = "wtHurt", r = "blast", parts = out, fire = rr.fire }) end
        local P = src and src.P
        if P and P.pl and G.P[P.pl] == P then G.R.Drive:FireClient(P.pl, { op = "wtHit", id = e.id, veh = d.id, r = "blast", kill = rr.kill, why = rr.why, fire = rr.fire, parts = out }) end
      end
    elseif #out > 0 then
      G.wtPush(e)
      msgTo(e, { op = "wtHurt", r = "blast", parts = out })
    end
    if frac >= 1.2 and e.alive then destroy(e, src, "crew") end   -- 一下打满一个多满血（重磅炸弹直接砸中）：整车完
  end

  ---------------------------------------------------------------- 每 0.25 秒：起火、维修、换位

  local acc = 0
  RunService.Heartbeat:Connect(function(dt)
    acc += dt
    if acc < 0.25 then return end
    local step = acc
    acc = 0
    local t = now()
    for _, e in ipairs(G.vehicles or {}) do
      local S = e.wt
      if S and e.alive then
        local changed = false
        if S.fireT then   -- 着火：每秒有机会烧伤一个乘员、烧发动机；烧够了自己灭
          local af = S.ammoFireT ~= nil   -- 弹药架起火：烧得凶，乘员挨烧快
          if math.random() < (af and 0.6 or 0.18) * step then
            local c = S.crew[math.random(1, #S.crew)]
            local out = {}
            hurt(e, c, af and 26 or 18, out, e.lastHitBy)
            if #out > 0 then msgTo(e, { op = "wtHurt", r = "fire", parts = out, fire = true }) end
          end
          local eng = S.byK.engine
          if eng and eng.hp > 0 and not af then eng.hp = math.max(0, eng.hp - 4 * step) end
          if t > (S.fireUntil or 0) then
            S.fireT = nil
            if af then
              S.ammoFireT = nil
              -- 烧完没灭：四成殉爆（弹架空了不炸）
              local rl = G.wtRackLeft and select(1, G.wtRackLeft(e, "ammo"))
              if (rl == nil or rl > 0) and math.random() < 0.4 then
                destroy(e, e.lastHitBy, "ammo")
                changed = false
              end
            end
            if e.alive then msgTo(e, { op = "wtFireOut" }) end
          end
          changed = true
          if e.alive and (alive(S) * 2 < S.total or alive(S) == 0) then destroy(e, e.lastHitBy, "fire") end
        end
        if S.fixT and t - S.fixT >= fixTime(e) then   -- 修好：坏了、毁了的模块都修到能用（六成），乘员救不回来
          S.fixT = nil
          for _, c in ipairs(S.mods) do if c.hp < c.max * 0.6 then c.hp = c.max * 0.6 end end
          msgTo(e, { op = "wtFixed" })
          changed = true
        elseif S.fixT then
          changed = true
        end
        if S.swap and t >= S.swap.t then   -- 别的乘员顶上关键位
          local sw = S.swap
          S.swap = nil
          local c = S.seat[sw.from]
          if c and c.hp > 0 and S.seat[sw.role] and S.seat[sw.role].hp <= 0 then
            local dead = S.seat[sw.role]
            S.seat[sw.role], S.seat[sw.from] = c, dead
            c.seat, dead.seat = sw.role, sw.from
            msgTo(e, { op = "wtSwapped", role = sw.role, from = sw.from })
          end
          scheduleSwap(e)
          changed = true
        end
        if changed and e.alive then G.wtPush(e) end
      end
    end
  end)

  -- 车里的人：维修（R 一下，十几秒，期间不能开炮）、灭火（有冷却）
  local function myVeh(P)
    local e = P and P.vehicle
    if e and e.wt and e.alive and (e.driver == P or table.find(e.pass or {}, P)) then return e end
    return nil
  end
  function G.ACT.wtFix(P)
    local e = myVeh(P)
    if not e then return end
    local S = e.wt
    if S.fixT then S.fixT = nil G.wtPush(e) return end   -- 再按一次取消
    local any = false
    for _, c in ipairs(S.mods) do if c.hp < c.max * 0.6 then any = true end end
    if not any then G.msg(P.pl, "info", "wt.noFix") return end
    if e.wtFx and not e.wtFx.repair then G.msg(P.pl, "bad", "wt.needParts") return end   -- 原厂车：没研究「零件」修不了
    S.fixT = now()
    G.wtPush(e)
  end
  function G.ACT.wtExt(P)
    local e = myVeh(P)
    if not e then return end
    local S = e.wt
    if not S.fireT then return end
    if e.wtFx and not e.wtFx.ext then G.msg(P.pl, "bad", "wt.needFpe") return end   -- 原厂车：没研究「灭火器」只能等火烧完
    if now() < (S.extT or 0) then G.msg(P.pl, "bad", "wt.extCd", math.ceil(S.extT - now())) return end
    S.fireT, S.ammoFireT = nil, nil
    S.extT = now() + EXT_CD
    msgTo(e, { op = "wtFireOut", ext = true })
    G.wtPush(e)
  end

  ---------------------------------------------------------------- 配弹、待发弹架（用户 11-25「全部都做」④）
  --   战雷：出车前选每种弹带几发（少带弹 = 少殉爆）；待发弹架（自动装弹机的转盘、西方坦克的炮塔尾舱）里的弹装得快，
  --   打空了装填手从车体弹架里拿、慢很多；不开炮的时候装填手把待发弹架补满。弹架打空了，打中它也不会殉爆。
  --   e.amL[wid] = { 弹种 = 几发 }（加起来 = st.mag + st.reserve）；e.rdy / e.rdyCap 待发弹架；属性 AmL、Rdy、RdyCap、RdyK 给客户端
  local BALs = require(RS:WaitForChild("Ballistics"))
  local VDa = require(RS:WaitForChild("VehDefs"))
  local SPLIT = { 5, 3, 2, 1, 1 }   -- 默认配弹：第一种五成多，往后越来越少
  local function mainGun(e)
    for _, wid in ipairs(e.def.weapons or {}) do
      local w = VDa.W[wid]
      if w and w.kind == "shell" and BALs.GUN[wid] and e.wst and e.wst[wid] then return wid, w, e.wst[wid] end
    end
    return nil
  end
  local function pushAmmo(e)
    if not e.model then return end
    local wid = mainGun(e)
    local L = wid and e.amL and e.amL[wid]
    if L then
      local bits = {}
      for _, k in ipairs(BALs.GUN[wid]) do table.insert(bits, k .. ":" .. (L[k] or 0)) end
      e.model:SetAttribute("AmL", table.concat(bits, ","))
    end
    if e.rdyCap then
      e.model:SetAttribute("Rdy", e.rdy)
      e.model:SetAttribute("RdyCap", e.rdyCap)
      e.model:SetAttribute("RdyK", (e.rdy > 0) and 1 or e.rdyEmptyK)
    end
  end
  -- P：出车的人（他在机库里配的弹，P.wtAmmo[科技树的键 / 型号]）；nil 按默认配
  function G.wtAmmoInit(e, P)
    if not e or not e.alive or not e.wst then return end
    local wid, w, st = mainGun(e)
    if not wid then return end
    local list = BALs.GUN[wid]
    local cap = (w.mag or 1) + (w.reserve or 0)
    local nA = e.wtFx and e.wtFx.ammo   -- 科技树改装：原厂只能打前几种
    local usable = {}
    for i, k in ipairs(list) do if not nA or i <= nA then table.insert(usable, k) end end
    local key = e.treeKey or e.def.id
    local want = P and P.wtAmmo and P.wtAmmo[key]
    local L = {}
    local sum = 0
    if type(want) == "table" then
      for _, k in ipairs(usable) do
        local n = math.max(0, math.floor(tonumber(want[k]) or 0))
        n = math.min(n, cap - sum)
        L[k] = n
        sum += n
      end
    end
    if sum <= 0 then   -- 没配过：按默认比例配满
      local tw = 0
      for i = 1, #usable do tw += SPLIT[i] or 1 end
      sum = 0
      for i, k in ipairs(usable) do
        L[k] = math.floor(cap * (SPLIT[i] or 1) / tw)
        sum += L[k]
      end
      L[usable[1]] += cap - sum
      sum = cap
    end
    e.amL = e.amL or {}
    e.amL[wid] = L
    e.amL0 = table.clone(L)   -- 配好的数（据点补给按它补）
    st.mag = math.min(w.mag or 1, sum)
    st.reserve = sum - st.mag
    local lay = W.prof(e.def).lay
    if lay == "e3" or lay == "w4" then
      e.rdyCap = e.def.rdyN or ((lay == "e3") and 22 or 15)   -- 转盘自动装弹机 22 发左右；西方坦克炮塔尾舱的待发弹 15 发左右
      e.rdyEmptyK = (lay == "e3") and 3 or 1.7                  -- 打空了：自动装弹机的车靠人从车体里拿（很慢）；装填手从车体弹架拿（慢七成）
      e.rdy = math.min(e.rdyCap, st.reserve)
    end
    pushAmmo(e)
  end
  -- Armor.lua 开火：这种弹还有吗（打光了换还有的那一种；一发都没有返回 false）
  function G.wtAmmoTake(e, wid, am, nA)
    local L = e.amL and e.amL[wid]
    local list = BALs.GUN[wid]
    if not L or not list then return am end
    am = am or list[1]
    local function usable(k) local i = table.find(list, k) return i ~= nil and (not nA or i <= nA) end
    if (L[am] or 0) <= 0 or not usable(am) then
      local alt = nil
      for _, k in ipairs(list) do if usable(k) and (L[k] or 0) > 0 then alt = k break end end
      if not alt then return false end
      am = alt
    end
    L[am] -= 1
    pushAmmo(e)
    return am
  end
  -- Armor.lua 开完一炮：下一发从哪拿——待发弹架还有就照常装，空了慢 rdyEmptyK 倍
  function G.wtRackK(e)
    if not e.rdyCap then return 1 end
    e.lastShot = now()
    local k = 1
    if e.rdy > 0 then e.rdy -= 1 else k = e.rdyEmptyK end
    pushAmmo(e)
    return k
  end
  -- 据点补给补回来的弹（⑧）：补给哪一种——离配好的数差得最多的那种
  function G.wtAmmoRefill(e, wid, add)
    local L = e.amL and e.amL[wid]
    if not L then return end
    local best, bk = -1, nil
    for k, n in pairs(L) do
      local cap0 = (e.amL0 and e.amL0[k]) or 0
      if cap0 - n > best then best, bk = cap0 - n, k end
    end
    bk = bk or BALs.GUN[wid][1]
    L[bk] = (L[bk] or 0) + add
    pushAmmo(e)
  end
  -- 车体弹架往待发弹架补（不开炮的时候）：据点补给那个每秒的循环里调
  local function rackStep(e)
    if not e.rdyCap or e.rdy >= e.rdyCap then return end
    local wid, w, st = mainGun(e)
    if not wid then return end
    local hull = st.reserve - e.rdy
    local t = now()
    if hull <= 0 or t - (e.lastShot or -99) < (w.rate or 6) * 1.5 or t < (e.rdyNext or 0) then return end
    e.rdy += 1
    e.rdyNext = t + (w.rate or 6) * ((e.rdyEmptyK >= 3) and 2 or 1.2)
    pushAmmo(e)
  end
  -- 这一块弹架里现在有几发、满的时候几发（打中弹架算殉爆用）
  local function rackLeft(e, k)
    if not e.rdyCap then return nil end
    local wid, w, st = mainGun(e)
    if not wid then return nil end
    if k == "ammo" then return e.rdy, e.rdyCap end
    local full = (w.mag or 1) + (w.reserve or 0) - e.rdyCap
    return math.max(0, st.reserve - e.rdy), math.max(1, full)
  end
  G.wtRackLeft = rackLeft
  -- 机库里配弹（客户端 WtAmmo.lua）：key 科技树的键（或型号），counts = { 弹种 = 几发 }；这一局内记着，下次出这辆车用
  function G.ACT.wtAmmoSet(P, key, counts)
    if type(key) ~= "string" or type(counts) ~= "table" then return end
    local c = {}
    local n = 0
    for k, v in pairs(counts) do
      if type(k) == "string" and BALs.AMMO[k] and type(v) == "number" then c[k] = math.clamp(math.floor(v), 0, 200) n += 1 end
      if n > 8 then break end
    end
    P.wtAmmo = P.wtAmmo or {}
    P.wtAmmo[key] = c
  end

  ---------------------------------------------------------------- 据点里补给（用户 11-25「全部都做」⑧）
  --   战雷：停在自己这队占着的据点里，弹药一发一发补回来、阵亡的乘员一个个补上。这里：车停着（一秒里挪不到 3 格）、
  --   在己方占着的据点圈里（占领圈的 1.6 倍）——每 4 秒补一发炮弹（机枪、机关炮一次补一个弹匣），每 10 秒补一个阵亡的乘员
  local SUP = { r = 1.6, ammoT = 4, crewT = 10, still = 3 }
  local VDs = require(RS:WaitForChild("VehDefs"))
  local function inOwnPoint(e, p)
    local CC = Config.Capture or { r = 70, height = 45 }
    local R2 = (CC.r * SUP.r) ^ 2
    for _, s in pairs(G.points or {}) do
      if s.owner == e.team and not s.locked then
        local dx, dz = p.X - s.x, p.Z - s.z
        if dx * dx + dz * dz < R2 and math.abs(p.Y - (s.y or p.Y)) < (CC.height or 45) then return true end
      end
    end
    return false
  end
  -- 补回来的乘员坐到空着的位子上（之前别人顶上去了的，就补顶上去那个人原来的位子）
  local function seatFor(S, c)
    for _, x in ipairs(S.crew) do
      local r = x.role
      local cur = S.seat[r]
      if not cur or cur.hp <= 0 or cur == c then return r end
    end
    return c.role
  end
  local function supplyStep(e)
    local p = e.root.CFrame.Position
    local moved = e.supP and (p - e.supP).Magnitude or 99
    e.supP = p
    if moved > SUP.still or not inOwnPoint(e, p) then e.supA, e.supC = nil, nil return end
    local t = now()
    e.supA = e.supA or (t + SUP.ammoT)
    e.supC = e.supC or (t + SUP.crewT)
    local gotAmmo, gotCrew = false, nil
    if t >= e.supA then
      e.supA = t + SUP.ammoT
      for wid, st in pairs(e.wst or {}) do
        local w = VDs.W[wid]
        if w then
          local full = (w.mag or 0) + (w.reserve or 0)
          if st.mag + st.reserve < full then
            local add = (w.kind == "shell" and (w.mag or 1) <= 1) and 1 or (w.mag or 1)   -- 主炮一发一发，机枪 / 机关炮一个弹匣
            st.reserve = math.min(full - st.mag, st.reserve + add)
            if G.wtAmmoRefill then G.wtAmmoRefill(e, wid, add) end   -- ④ 配弹：按弹种记的也补
            gotAmmo = true
          end
        end
      end
    end
    local S = e.wt
    if S and t >= e.supC then
      e.supC = t + SUP.crewT
      for _, c in ipairs(S.crew) do
        if c.hp <= 0 then
          c.hp = c.max
          local r = seatFor(S, c)
          c.seat = r
          S.seat[r] = c
          gotCrew = r
          break
        end
      end
      if gotCrew then G.wtPush(e) end
    end
    if gotAmmo or gotCrew then msgTo(e, { op = "wtSupply", ammo = gotAmmo or nil, crew = gotCrew }) end
  end
  task.spawn(function()
    while true do
      task.wait(1)
      if G.round and G.round.phase == "battle" and G.points then
        for _, e in ipairs(G.ents) do
          if e.alive and e.wst and e.root and not e.air and not e.sea and (e.cat == "armor" or e.cat == "light") then
            local okS, err = pcall(supplyStep, e)
            if not okS then warn("[战雷] 据点补给出错：" .. tostring(err)) end
            pcall(rackStep, e)   -- ④ 不开炮的时候补待发弹架
          end
        end
      end
    end
  end)
end

return Wt
