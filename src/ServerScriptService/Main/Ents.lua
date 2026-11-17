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

  local folder = Instance.new("Folder")
  folder.Name = "Ents"
  folder.Parent = workspace
  G.entFolder = folder

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
    root.CanCollide = def.solid == true
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

  -- 打实体：amt 已经乘过倍数；src = { P, name, team }
  function G.damageEnt(e, amt, src)
    if not e or not e.alive or amt <= 0 then return end
    if src and src.team == e.team then return end
    if e.invuln then return end
    e.hp -= amt
    e.lastHitBy = src
    e.model:SetAttribute("Hp", math.max(0, math.floor(e.hp)))
    if src and src.P and src.P.pl then G.R.Msg:FireClient(src.P.pl, "hit", (e.hp <= 0) and "kill" or "hit") end
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
      if e.headTop and hitPos and hitPos.Y > e.root.CFrame.Position.Y + e.root.Size.Y / 2 - e.headTop then k = headMul or 1 end
      G.damageEnt(e, dmg * mult(w, e.cat) * k, src)
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
    local r = w.splash or 8
    G.fx({ k = "boom", p = pos, s = scale or (r / 12), c = boomKind(w) })
    for _, P in pairs(G.P) do
      local char = P.char
      local hrp = char and char:FindFirstChild("HumanoidRootPart")
      if hrp and P.alive and not G.inVeh(P) then   -- 在车里的人由车挨炸（遥控无人机的人在地上，照样挨炸）
        local d = (hrp.Position - pos).Magnitude
        if d < r then G.hurtChar(char, w.dmg * mult(w, "inf") * (1 - 0.7 * d / r), src) end
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
      f = s.w and s.w.fx or nil, w = s.w and s.w.id or nil, by = s.byEnt })
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
      if s.step then   -- 自己带导引的弹（机载导弹、制导炸弹、火箭弹）：每步先由它改速度；返回 true 是已经炸了
        local ok, r = pcall(s.step, s, dt)
        if not ok then G.reportError("导引", r) done = true elseif r then done = true end
      elseif s.target then   -- 追踪：导弹朝目标拐（过载有限）
        local tg = s.target
        if tg.alive then
          local want = (tg.root.CFrame.Position - s.pos).Unit * s.vel.Magnitude
          s.vel = s.vel:Lerp(want, math.clamp(dt * 3.2, 0, 1))
          if (tg.root.CFrame.Position - s.pos).Magnitude < 12 then
            G.explode(s.pos, s.w, s.src)
            done = true
          end
        end
      end
      if not done then
        if s.grav then s.vel += GRAV * (s.gscale or 1) * dt end
        local step = s.vel * dt
        params.FilterDescendantsInstances = s.ignore or {}
        local res = workspace:Raycast(s.pos, step, params)
        if res and s.kind == "shell" then   -- 炮弹：直接命中算足伤害，再炸一圈（三成）
          if res.Instance then hitThing(res.Instance, s.w, s.w.dmg, s.src, 1, res.Position) end
          s.w.splashW = s.w.splashW or { dmg = s.w.dmg * 0.3, splash = s.w.splash, vs = s.w.vs,
            boom = (s.w.fx == "agun" or s.w.fx == "ac" or s.w.fx == "lmg") and "gun" or "shell" }   -- 航炮、高炮、小口径：小火光；坦克、舰炮：炮弹
          G.explode(res.Position, s.w.splashW, s.src, (s.w.splash or 6) / 10)
          done = true
        elseif res and s.kind ~= "grenade" then
          G.explode(res.Position, s.w, s.src)
          if res.Instance and s.kind == "rocket" then hitThing(res.Instance, s.w, s.w.dmg * 0.3, s.src) end   -- 直接命中多一点
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
        if not done and (s.t > (s.life or 8) or s.pos.Y < -Map.SEA_DEPTH) then
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
