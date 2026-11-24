-- Roblox全面大战场——实体与伤害
--   实体（机器人、载具、舰艇、工事、登陆艇）：服务器上一个 Model + 锚定的隐形命中盒 Root，类型、队伍、血量写在属性里；
--     客户端按属性克隆模板、平滑地跟着 Root 走（View.lua）；伤害按目标类别（inf 步兵、light 轻型车、armor 装甲、air 飞机、ship 舰艇、fort 工事）乘武器的倍数
--   飞行中的弹：火箭弹、手雷、防空导弹（追踪）、迫击炮弹、炮弹——每一步射线检测，落地 / 打中就爆炸
--   爆炸：半径内按距离衰减，打实体和玩家角色（不伤自己人）
local Ents = {}

function Ents.init(G)
  local Config, Map = G.Config, G.Map
  local V = Vector3.new
  local GRAV = V(0, -workspace.Gravity * 0.55, 0)   -- 弹道用的重力（比角色的轻一点，火箭弹、手雷飞得远一点）
  local HitSurf = require(game:GetService("ReplicatedStorage"):WaitForChild("HitSurf"))

  local folder = Instance.new("Folder")
  folder.Name = "Ents"
  folder.Parent = workspace
  G.entFolder = folder

  -- 流式加载（地点文件里 Workspace.StreamingEnabled 开着时；用户 11-24 晚「streaming 优化」）：客户端只收到身边一片的地图零件和地形。
  --   一直要在的（雷达、标记、瞄准、队友、敌舰都要看全图的）设成 Persistent：实体代理（一个隐形的命中盒 Root，很轻）、玩家角色、舰队、据点；
  --   玩家出生到远处、遥控无人机飞远，先请服务器把那一片送过去（RequestStreamAroundAsync / AddReplicationFocus）。没开 streaming 时这些都不起作用
  G.streaming = false
  pcall(function() G.streaming = workspace.StreamingEnabled == true end)
  function G.persist(model)
    if model then pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end) end
  end
  function G.streamAround(pl, pos, timeout)
    if not G.streaming or not pl or typeof(pos) ~= "Vector3" then return end
    local ch = pl.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp and (hrp.Position - pos).Magnitude < 400 then return end   -- 就在身边（最小半径 512 以内本来就在）：不用等
    pcall(function() pl:RequestStreamAroundAsync(pos, timeout or 3) end)
  end
  function G.streamFocus(pl, part, on)
    if not G.streaming or not pl or not part then return end
    pcall(function()
      if on then pl:AddReplicationFocus(part) else pl:RemoveReplicationFocus(part) end
    end)
  end

  local ents, byId, nextId = {}, {}, 0
  G.ents, G.entById = ents, byId

  -- 新实体：def = { kind（编号，客户端按它挑模板）, team, cat（伤害类别）, hp, size（命中盒）, cf, owner（开的人）, air, sea }
  function G.newEnt(def)
    nextId += 1
    local id = "e" .. nextId
    local m = Instance.new("Model")
    m.Name = id
    local root = Instance.new("Part")
    root.Name = "Root"
    root.Anchored = true
    -- 挡人改在客户端按真正的模型做（View.lua 的 solidSet）：服务器的方盒按型号表的长宽高，跟外形对不上（用户：模型的实体和模型对不上），只管挨打
    root.CanCollide = false
    root.CanTouch = false
    root.CanQuery = true
    root.Transparency = 1
    root.Size = def.size or V(4, 5, 4)
    root.CFrame = def.cf or CFrame.new()
    root.Parent = m
    m.PrimaryPart = root
    m:SetAttribute("EntId", id)
    m:SetAttribute("Kind", def.kind)
    m:SetAttribute("Team", def.team)
    m:SetAttribute("Cat", def.cat)
    m:SetAttribute("Hp", def.hp)
    m:SetAttribute("MaxHp", def.hp)
    G.persist(m)   -- 全图都要看得见（雷达、标记、队友、瞄准）：不随 streaming 流出去
    local e = { id = id, model = m, root = root, kind = def.kind, team = def.team, cat = def.cat or "light", hp = def.hp or 100, maxHp = def.hp or 100,
      air = def.air, sea = def.sea, alive = true, born = os.clock(), data = def.data or {} }
    for k, v in pairs(def.extra or {}) do e[k] = v end
    m.Parent = folder
    table.insert(ents, e)
    byId[id] = e
    return e
  end

  function G.moveEnt(e, cf)
    e.root.CFrame = cf
  end

  function G.removeEnt(e)
    if not byId[e.id] then return end
    byId[e.id] = nil
    for i, x in ipairs(ents) do
      if x == e then table.remove(ents, i) break end
    end
    e.alive = false
    if e.model then e.model:Destroy() end
  end

  -- 打中的零件属于哪个实体（往上找带 EntId 的 Model）
  function G.entOf(inst)
    local m = inst
    while m and m ~= workspace do
      if m:IsA("Model") then
        local id = m:GetAttribute("EntId")
        if id then return byId[id] end
      end
      m = m.Parent
    end
    return nil
  end

  -- 打实体：amt 已经乘过倍数；src = { P, name, team }；head：打在小兵头上
  --   给开枪的真人的命中提示（客户端的命中叉、加分、连杀）：hit / head、打死 kill / headkill、打掉车船 vkill、工事 fkill
  function G.damageEnt(e, amt, src, head)
    if not e or not e.alive or amt <= 0 then return end
    if src and src.team == e.team then return end
    if e.invuln then return end
    local dk = G.dmgK and G.dmgK[e]   -- 爆反挡下的这一发（Era.lua）：直接命中、爆炸都只剩几成
    if dk then amt *= dk end
    e.hp -= amt
    e.lastHitBy = src
    e.model:SetAttribute("Hp", math.max(0, math.floor(e.hp)))
    if src and src.P and src.P.pl then
      local k
      if e.hp <= 0 then
        k = (e.cat == "inf") and (head and "headkill" or "kill") or ((e.cat == "fort") and "fkill" or "vkill")
      else
        k = head and "head" or "hit"
      end
      G.R.Msg:FireClient(src.P.pl, "hit", k)
    end
    if e.onHit then G.try("挨打", e.onHit, e, amt, src) end
    if e.hp <= 0 then
      e.alive = false
      if e.cat ~= "inf" then G.fx({ k = "boom", p = e.root.CFrame.Position, s = (e.cat == "ship") and 3 or 2, c = "wreck" }) end   -- 步兵倒下不炸（客户端画倒地）
      if src and src.P and G.P[src.P.pl] == src.P and e.cat ~= "inf" and e.cat ~= "fort" then G.addScore(src.P, Config.Score.vehicleKill) end
      if e.onDeath then G.try("被毁", e.onDeath, e, src) else G.removeEnt(e) end
    end
  end

  -- 武器对某类目标的倍数
  local function mult(w, cat) return (w.vs and w.vs[cat]) or 1 end
  G.mult = mult

  -- 一个零件的伤害类别：玩家角色是 inf；实体按 cat；hitPos 打中的点（机器人上半截 headTop 格算爆头）
  local function hitThing(inst, w, dmg, src, headMul, hitPos)
    local e = G.entOf(inst)
    if e then
      local k = 1
      local hb = e.hit or e.root   -- 小兵的命中零件随姿势变（Bots.lua）
      local head = e.headTop ~= nil and hitPos ~= nil and hitPos.Y > hb.CFrame.Position.Y + hb.Size.Y / 2 - e.headTop
      if head then k = headMul or 1 end
      G.damageEnt(e, dmg * mult(w, e.cat) * k, src, head and (headMul or 1) > 1)
      return true
    end
    local char = inst:FindFirstAncestorOfClass("Model")
    while char and not char:FindFirstChildOfClass("Humanoid") do char = char:FindFirstAncestorOfClass("Model") end
    if char then
      local k = (inst.Name == "Head") and (headMul or 1) or 1
      return G.hurtChar(char, dmg * mult(w, "inf") * k, src, inst)
    end
    return false
  end
  G.hitThing = hitThing

  -- 爆炸的样子（客户端 Fx 按它画、按它出声）：gun 航炮 / 小口径炮弹，nade 手雷、炸药，shell 炮弹、地雷，rkt 火箭弹，msl 导弹，
  --   bomb 炸弹，flak 高炮空炸；w.boom 直接指定
  local function boomKind(w)
    if w.boom then return w.boom end
    local k = w.kind
    if k == "bomb" or w.id == "pgm" or w.id == "cluster" then return "bomb" end
    if w.id == "gunrun" then return "gun" end
    if k == "aam" or k == "agm" or k == "missile" or k == "sam" or k == "lock" then return "msl" end
    if k == "rkt" or k == "proj" then return "rkt" end
    if k == "flak" then return "flak" end
    if k == "throw" or k == "place" then return "nade" end
    if k == "shell" or k == "arty" or k == "mortar" or w.trig then return "shell" end
    return nil
  end
  G.boomKind = boomKind

  -- 爆炸：半径 splash 内按距离线性衰减（中心全伤，边上三成）
  function G.explode(pos, w, src, scale)
    if w and w.nuke and G.nukeAt then return G.nukeAt(pos, w, src) end   -- 核导弹撞到地面 / 房子：照样核爆（Nuke.lua）
    local r = w.splash or 8
    local ownK = false
    if not G.dmgK and G.eraBlast then
      local m = G.eraBlast(pos, w, G.blastDir)
      if m then G.dmgK, ownK = m, true end
    end
    G.fx({ k = "boom", p = pos, s = scale or (r / 12), c = boomKind(w) })
    for _, P in pairs(G.P) do
      local char = P.char
      local hrp = char and char:FindFirstChild("HumanoidRootPart")
      if hrp and P.alive and not G.inVeh(P) then   -- 在车里的人由车挨炸（遥控无人机的人在地上，照样挨炸）
        local d = (hrp.Position - pos).Magnitude
        if d < r then
          G.boomAt = pos   -- 受伤方向按炸点（Round.lua 的 hurtChar）
          G.hurtChar(char, w.dmg * mult(w, "inf") * (1 - 0.7 * d / r), src)
          G.boomAt = nil
        end
      end
    end
    for _, e in ipairs(table.clone(ents)) do
      if e.alive then
        local d
        if e.ship then   -- 长条的舰艇：按到船体方块的距离（按中心减四成长度算的话，船头外一百多格的落点也算炸着）
          local l = e.root.CFrame:PointToObjectSpace(pos)
          local hs = e.root.Size / 2
          local dx, dy, dz = math.max(0, math.abs(l.X) - hs.X), math.max(0, math.abs(l.Y) - hs.Y), math.max(0, math.abs(l.Z) - hs.Z)
          d = math.sqrt(dx * dx + dy * dy + dz * dz)
        else
          d = (e.root.CFrame.Position - pos).Magnitude - math.max(e.root.Size.X, e.root.Size.Z) * 0.4
        end
        if d < r then G.damageEnt(e, w.dmg * mult(w, e.cat) * (1 - 0.7 * math.max(0, d) / r), src) end
      end
    end
    if G.onExplode then G.onExplode(pos, w, src) end
    if ownK then G.dmgK = nil end
  end

  ---------------------------------------------------------------- 飞行中的弹

  local shots = {}   -- { pos, vel, w, src, grav, fuse, target, t, ignore, kind }
  G.shots = shots
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.IgnoreWater = false

  local shotN = 0
  function G.launch(s)
    s.t = 0
    shotN += 1
    s.id = shotN
    table.insert(shots, s)
    G.fx({ k = "shot", id = s.id, p = s.pos, v = s.vel, kind = s.kind, g = s.grav and true or false, gs = s.gscale, tg = s.tgId or (s.target and s.target.id) or nil,
      f = s.w and s.w.fx or nil, w = s.w and s.w.id or nil, by = s.byEnt, dr = s.drag, tr = s.tracer })   -- dr 空气阻力、tr 曳光（坦克炮弹，Ballistics.lua）
    return s
  end

  -- 迫击炮弹、炮弹：flight 秒后落在 pos（落点已经算好散布）
  function G.shell(pos, w, src, flight, from)
    G.fx({ k = "shell", p = pos, t = flight, a = from })
    task.delay(flight, function() G.explode(pos, w, src) end)
  end

  local function stepShots(dt)
    for i = #shots, 1, -1 do
      local s = shots[i]
      s.t += dt
      local done = false
      if G.apsCheck and (s.kind == "rocket" or s.kind == "missile") and G.apsCheck(s, dt) then   -- 被坦克的主动防御打掉了（Aps.lua）
        done = true
      elseif s.step then   -- 自己带导引的弹（机载导弹、制导炸弹、火箭弹）：每步先由它改速度；返回 true 是已经炸了
        G.blastDir = s.vel   -- 导引弹自己引爆时（step 里调 G.explode）爆反按这个来向找块
        local ok, r = pcall(s.step, s, dt)
        G.blastDir = nil
        if not ok then G.reportError("导引", r) done = true elseif r then done = true end
      elseif s.target then   -- 追踪：导弹朝目标拐（过载有限）
        local tg = s.target
        if tg.alive then
          local want = (tg.root.CFrame.Position - s.pos).Unit * s.vel.Magnitude
          s.vel = s.vel:Lerp(want, math.clamp(dt * 3.2, 0, 1))
          if (tg.root.CFrame.Position - s.pos).Magnitude < 12 then
            G.blastDir = s.vel
            G.explode(s.pos, s.w, s.src)
            G.blastDir = nil
            done = true
          end
        end
      end
      if not done then
        if s.grav then s.vel += GRAV * (s.gscale or 1) * dt end
        -- 空气阻力（坦克炮弹，Ballistics.lua：a = −k·v·|v|，k 每格）：脱壳穿甲弹每公里掉五六十米 / 秒，破甲弹掉一百多
        if s.drag then s.vel -= s.vel * math.min(0.5, s.drag * s.vel.Magnitude * dt) end
        local step = s.vel * dt
        params.FilterDescendantsInstances = s.ignore or {}
        local res = workspace:Raycast(s.pos, step, params)
        local ricE = res and s.kind == "shell" and not s.ricocheted and res.Instance and G.entOf(res.Instance) or nil
        local RIC = G.Config.Ricochet
        local bounced = false
        if ricE and RIC and ricE.alive and RIC.a0[ricE.cat] then
          -- 跳弹（用户：跳弹也做出来）：炮弹打在坦克、装甲车上，入射方向和装甲面的法线夹角越大越容易滑开（a0 度起有可能、a1 度一定）
          local vd = s.vel.Unit
          local ang = math.deg(math.acos(math.clamp(math.abs(vd:Dot(res.Normal)), 0, 1)))
          local k = math.clamp((ang - RIC.a0[ricE.cat]) / math.max(1, RIC.a1[ricE.cat] - RIC.a0[ricE.cat]), 0, 1)
          if k > 0 and math.random() < k then
            local n = res.Normal
            local refl = vd - 2 * vd:Dot(n) * n
            refl = (refl + V((math.random() - 0.5) * 0.16, math.random() * 0.08, (math.random() - 0.5) * 0.16)).Unit
            s.vel = refl * s.vel.Magnitude * RIC.keep
            s.pos = res.Position + n * 0.5
            s.ricocheted = true
            s.life = s.t + RIC.life
            if RIC.dmg > 0 then G.damageEnt(ricE, s.w.dmg * RIC.dmg, s.src) end
            G.fx({ k = "ricochet", id = s.id, p = s.pos, v = s.vel, n = n })
            local P = s.src and s.src.P
            if P and P.pl then G.msg(P.pl, "ric", "hit.ric") end
            local D = ricE.driver
            if D and D.pl then G.msg(D.pl, "ric", "hit.ricIn") end
            G.ricochets = (G.ricochets or 0) + 1   -- 测试用
            bounced = true
          end
        end
        if bounced then
          -- 刚跳开：位置、速度上面已经改好了
        elseif res and s.ricocheted then   -- 跳开过的弹：再碰到东西就没了（不炸、不伤），碰的地方迸一点火星
          G.fx({ k = "spark", p = res.Position, n = res.Normal, h = "m", s = 1 })
          done = true
        elseif res and s.kind == "shell" then   -- 炮弹：直接命中算足伤害，再炸一圈（三成）
          local hitE = res.Instance and G.eraShell and G.entOf(res.Instance)
          local ek = hitE and G.eraShell(hitE, s, res.Position)   -- 重型爆反挡穿甲弹（Era.lua）
          if ek then G.dmgK = { [hitE] = ek } end
          if res.Instance then hitThing(res.Instance, s.w, s.w.dmg, s.src, 1, res.Position) end
          -- 炮弹、航炮直接打在车、船、飞机上：钢甲上迸一团白热的火花（客户端 Fx 的 spark；大小按口径：坦克炮 2 倍，航炮 1.25 倍）
          local hs = res.Instance and HitSurf.of(res.Instance, res.Material)
          if hs and HitSurf.METAL[hs] then
            G.fx({ k = "spark", p = res.Position, n = res.Normal, h = hs, s = math.clamp((s.w.cal or 0.25) * 5, 1, 3) })
          end
          s.w.splashW = s.w.splashW or { dmg = s.w.dmg * 0.3, splash = s.w.splash, vs = s.w.vs,
            boom = (s.w.fx == "agun" or s.w.fx == "ac" or s.w.fx == "lmg") and "gun" or "shell" }   -- 航炮、高炮、小口径：小火光；坦克、舰炮：炮弹
          G.explode(res.Position, s.w.splashW, s.src, (s.w.splash or 6) / 10)
          if ek then G.dmgK = nil end
          done = true
        elseif res and s.kind == "rocket" and G.kitRocket and G.kitRocket(s, res) then
          -- 火箭弹打在坦克的栅栏装甲上、引信被卡坏：哑火（Kit.lua），不炸
          done = true
        elseif res and s.kind ~= "grenade" then
          -- 火箭弹、导弹：爆反按来向找块，这一发的爆炸和直接命中都按它打折（G.dmgK 在两下之间都留着）
          local m = G.eraBlast and G.eraBlast(res.Position, s.w, s.vel)
          if m then G.dmgK = m end
          G.explode(res.Position, s.w, s.src)
          if res.Instance and s.kind == "rocket" then hitThing(res.Instance, s.w, s.w.dmg * 0.3, s.src) end   -- 直接命中多一点
          if m then G.dmgK = nil end
          done = true
        elseif res and s.kind == "grenade" then   -- 手雷：落地弹一下、滚一点，等引信
          s.pos = res.Position + res.Normal * 0.6
          s.vel = (s.vel - 1.6 * s.vel:Dot(res.Normal) * res.Normal) * 0.35
        else
          s.pos += step
        end
        if not done and s.fuse and s.t >= s.fuse then
          G.explode(s.pos, s.w, s.src)
          done = true
        end
        if not done and (s.t > (s.life or 8) or (s.pos.Y < -1.5 and Map.height(s.pos.X, s.pos.Z) < -1.5)) then   -- 掉进海里：水面上溅起水花（海加深以后不能等沉到海底）
          if s.kind ~= "grenade" then G.fx({ k = "splash", p = V(s.pos.X, 0, s.pos.Z) }) end
          done = true
        end
      end
      if done then
        table.remove(shots, i)
        G.fx({ k = "shotEnd", id = s.id })
      end
    end
  end

  function G.entsStep(dt)
    stepShots(dt)
    for _, e in ipairs(table.clone(ents)) do
      if e.alive and e.step then G.try("实体 " .. e.kind, e.step, e, dt) end
    end
  end

  -- 圈里的机器人、地面载具（占领用）：返回攻方数、守方数
  function G.countAt(x, z, y, r)
    local a, d = 0, 0
    local r2 = r * r
    for _, e in ipairs(ents) do
      if e.alive and e.counts and not e.air and not e.sea then
        local p = e.root.CFrame.Position
        local dx, dz = p.X - x, p.Z - z
        if dx * dx + dz * dz < r2 and math.abs(p.Y - y) < 45 then
          if e.team == "atk" then a += (e.counts or 1) else d += (e.counts or 1) end
        end
      end
    end
    return a, d
  end
end

return Ents
