-- Roblox全面大战场——地面载具（坦克、装甲车、防空、火炮）：部署（名额、冷却）、开车（位置由开车的客户端算，服务器查速度、查下水）、
--   开火（主炮炮弹有弹道、并列机枪直射、榴弹炮 / 火箭炮曲射）、烟幕弹（从型号规定的发射筒打出去，落地起烟团，挡住机器人的视线）、
--   下车 / 上车、被毁（车组阵亡、残骸烧一会儿、这个名额冷却）
--   车都在地图里的生成点生成（Depots.lua）：守方营地车场；攻方登陆平台旁的水面——两栖的自己游，不会游的站在 726 气垫艇上连艇一起开，冲上岸放下车
local RS = game:GetService("ReplicatedStorage")

local Armor = {}

function Armor.init(G)
  local Config, Map = G.Config, G.Map
  local VD = require(RS:WaitForChild("VehDefs"))
  local FD = require(RS:WaitForChild("FortDefs"))
  local V = Vector3.new
  local CF = CFrame.new
  local now = os.clock
  local CATS = Config.VehicleCats
  local SM = VD.SMOKE
  local GROUND = { tank = true, apc = true, aa = true, arty = true }

  local vehicles = {}   -- 活着的载具实体
  local pending = { atk = {}, def = {} }   -- [cat] = { 冷却到什么时候, … }（被毁的车占着名额）
  G.vehicles = vehicles

  ---------------------------------------------------------------- 名额

  local function used(team, cat)
    local n = 0
    for _, e in ipairs(vehicles) do
      if e.alive and e.team == team and e.vcat == cat and not e.ai then n += 1 end   -- AI 开的车（AIVeh.lua）不占玩家的名额
    end
    local t = now()
    local list = pending[team][cat] or {}
    for i = #list, 1, -1 do
      if list[i] <= t then table.remove(list, i) else n += 1 end
    end
    pending[team][cat] = list
    return n
  end
  -- 每类：在用、上限、要等多久（满了而且有在冷却的）
  function G.vehAvail(team)
    local out = {}
    local tn = G.teamCount(team)
    for cat in pairs(GROUND) do
      local cap = Config.VehicleCap(cat, tn)
      local u = used(team, cat)
      local cd = 0
      if u >= cap then
        local t, soon = now(), math.huge
        for _, x in ipairs(pending[team][cat] or {}) do soon = math.min(soon, x) end
        if soon < math.huge then cd = math.ceil(soon - t) end
      end
      out[cat] = { u = u, cap = cap, cd = cd }
    end
    return out
  end

  -- 这一队能开的型号（爱国者要等有飞机）
  function G.vehModels(team)
    local out = {}
    for _, cat in ipairs(Config.VehicleOrder) do
      if GROUND[cat] then
        for _, id in ipairs(Config.Vehicles[team][cat] or {}) do
          local d = VD.get(id)
          if d and not d.needsAir then table.insert(out, id) end
        end
      end
    end
    return out
  end

  ---------------------------------------------------------------- 摆车

  -- (x, z) 附近一块够平、够大的地（四个角高度差小）
  -- 车头前方 ahead 格的路能不能开出去：坡不比 Drive.lua 能爬的陡、不下海、不顶着房子 / 帐篷 / 旗杆 / 工事（面朝 ±Z 时按轴对齐的方框查）
  local function laneClear(px, pz, d, face, ahead)
    local h0 = Map.height(px, pz)
    for s = d.L * 0.5 + 4, d.L * 0.5 + ahead, 4 do
      local h1 = Map.height(px + face.X * s, pz + face.Z * s)
      if h1 < 0.6 or (h1 - h0) / 4 > 0.7 then return false end
      h0 = h1
    end
    if not G.spotClear then return true end
    local mid = d.L * 0.5 + ahead * 0.5
    return G.spotClear(px + face.X * mid, pz + face.Z * mid, d.W * 0.5 + 1, ahead * 0.5, d.H)
  end
  -- face：车头朝哪（给了就再要求车头前方几个车长开得出去——营地里车头正对着房子、旗杆的话一出生就开不动）
  local function parkAt(x, z, r0, r1, d, face)
    for try = 1, 60 do
      local a, r = math.random() * math.pi * 2, r0 + math.random() * (r1 - r0)
      local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
      local ok = true
      local hs = {}
      for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        local h = Map.height(px + o[1] * d.W * 0.5, pz + o[2] * d.L * 0.5)
        if h < 0.6 then ok = false break end
        table.insert(hs, h)
      end
      if ok then
        local lo, hi = math.min(table.unpack(hs)), math.max(table.unpack(hs))
        -- 还要空着：不压在房子、帐篷、工事、钢刺猬上（Forts 的 G.spotClear）；前 40 次还要车头前方开得出去，找不到再放宽
        if hi - lo < d.L * 0.18 and (not G.spotClear or G.spotClear(px, pz, d.W * 0.5 + 1, d.L * 0.5 + 1, d.H))
          and (not face or try > 40 or laneClear(px, pz, d, face, d.L * 3)) then return px, pz end
      end
    end
    return x, z
  end
  -- 车底在 (x, z)、朝向 face 时的车底 CFrame（按四个角的地面高度定俯仰、侧倾）
  local function baseAt(d, x, z, face)
    face = V(face.X, 0, face.Z)
    if face.Magnitude < 0.01 then face = V(0, 0, -1) end
    face = face.Unit
    local right = V(-face.Z, 0, face.X)
    local function gh(p) return Map.ground(p.X, p.Z) end
    local c = V(x, 0, z)
    local f, b = c + face * d.L * 0.4, c - face * d.L * 0.4
    local l, r = c - right * d.W * 0.4, c + right * d.W * 0.4
    local yf, yb, yl, yr = gh(f), gh(b), gh(l), gh(r)
    local y = (yf + yb + yl + yr) / 4
    -- 坡顶、山脊上四角的平面会切进地里：车底下再取 9 个点，冒出平面就整车抬起来（同客户端 Drive.lua）
    local gf, gr = (yf - yb) / (d.L * 0.8), (yr - yl) / (d.W * 0.8)
    local lift = 0
    for _, u in ipairs({ -0.45, 0, 0.45 }) do
      for _, s in ipairs({ -0.45, 0, 0.45 }) do
        local p = c + face * (u * d.L) + right * (s * d.W)
        local over = gh(p) - (y + gf * u * d.L + gr * s * d.W)
        if over > lift then lift = over end
      end
    end
    if lift > 0.2 then y += lift - 0.2 end
    local fwd = (V(f.X, yf, f.Z) - V(b.X, yb, b.Z)).Unit
    local side = (V(r.X, yr, r.Z) - V(l.X, yl, l.Z)).Unit
    local up = side:Cross(fwd).Unit
    return CFrame.fromMatrix(V(x, y, z), side, up, -fwd)
  end
  G.vehBaseAt = baseAt
  local function rootFromBase(d, base) return base * CF(0, d.H / 2, 0) end
  local function baseOf(e) return e.root.CFrame * CF(0, -e.def.H / 2, 0) end
  G.vehBaseOf = baseOf

  ---------------------------------------------------------------- 车组（开车的人）

  local function hideChar(char, on)
    for _, p in ipairs(char:GetDescendants()) do
      if p:IsA("BasePart") or p:IsA("Decal") then
        if on then
          if p:GetAttribute("T0") == nil then p:SetAttribute("T0", p.Transparency) end
          p.Transparency = 1
        else
          local t0 = p:GetAttribute("T0")
          if t0 ~= nil then p.Transparency = t0 p:SetAttribute("T0", nil) end
        end
      end
    end
  end

  local function seat(P, e)
    local char = P.char
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.Anchored = true end
    hideChar(char, true)
    P.vehicle = e
    e.driver = P
    e.emptyAt = nil
    e.model:SetAttribute("Driver", P.pl.UserId)
    char:PivotTo(e.root.CFrame)
    G.pushOne(P)
  end

  local function unseat(P, e, place)
    if P.vehicle == e then P.vehicle = nil end
    if e.driver == P then
      e.driver = nil
      e.emptyAt = now()
      e.model:SetAttribute("Driver", 0)
    end
    local char = P.char
    if char and char.Parent and place then
      hideChar(char, false)
      local hrp = char:FindFirstChild("HumanoidRootPart")
      local base = baseOf(e)
      local side = base * CF(-(e.def.W / 2 + 4), 0, 0)
      local x, z = side.Position.X, side.Position.Z
      if hrp then hrp.Anchored = false end
      char:PivotTo(CFrame.lookAt(V(x, Map.ground(x, z) + 3.5, z), V(x, Map.ground(x, z) + 3.5, z) + base.LookVector))
    end
    G.pushOne(P)
  end

  ---------------------------------------------------------------- 新车、被毁

  local function newVehicle(team, id, base, P)
    local d = VD.get(id)
    local c = CATS[d.cat]
    local mod = Config.VehicleMod[id] or {}
    local hp = math.floor(c.hp * (mod.hp or 1))
    -- solid：车是实心的，人走不过去、能站上去（用户：让载具建模变成实体）；开车、坐车的人锚定在车里，不受影响
    local e = G.newEnt({ kind = "veh", team = team, cat = c.tgt, hp = hp, size = V(d.W, d.H, d.L), cf = rootFromBase(d, base), solid = true,
      extra = { def = d, vcat = d.cat } })   -- 占领时不单算车：开车的人照常算一个
    e.model:SetAttribute("Model", id)
    e.model:SetAttribute("Ty", 0)
    e.model:SetAttribute("Gp", 0)
    e.model:SetAttribute("Driver", 0)
    e.ty, e.gp = 0, 0
    e.smokeLeft = SM.salvos
    e.smokeNext = 0
    e.wst = {}
    for _, wid in ipairs(d.weapons) do
      local w = VD.W[wid]
      e.wst[wid] = { mag = w.mag, reserve = w.reserve or 0, next = 0 }
    end
    e.lastSync = now()
    e.onDeath = function(self, src)
      G.try("载具被毁", function()
        self.alive = false
        self.wreck = true
        self.model:SetAttribute("Wreck", true)
        G.fx({ k = "boom", p = self.root.CFrame.Position, s = 2.4, c = "wreck" })
        G.fx({ k = "wreck", id = self.id, p = self.root.CFrame.Position, life = 25 })
        if not self.ai then   -- AI 的车被毁不给玩家记冷却
          local list = pending[self.team][self.vcat] or {}
          table.insert(list, now() + (CATS[self.vcat].cd or 60))
          pending[self.team][self.vcat] = list
        end
        local D = self.driver
        if D then
          self.driver = nil
          D.vehicle = nil
          if D.char then
            hideChar(D.char, false)
            G.hurtChar(D.char, 1e5, src)
          end
          G.msg(D.pl, "bad", "ui.vehLost")
        end
        if src and src.P and G.P[src.P.pl] == src.P then G.msg(src.P.pl, "kill", "ui.vehKilled", { k = "veh." .. self.def.id }) end
        for i, x in ipairs(vehicles) do
          if x == self then table.remove(vehicles, i) break end
        end
      end)
      task.delay(25, function() G.removeEnt(self) end)
    end
    table.insert(vehicles, e)
    return e
  end
  G.newVehicle = newVehicle   -- AIVeh.lua：AI 开的车

  ---------------------------------------------------------------- 气垫艇（攻方不会游的车：登陆平台旁边站在气垫艇上生成，开车的人连艇一起开，冲上岸放下车、艇自己回去）

  local lcacs = {}
  local LCAC = VD.LCAC   -- 同登陆艇：岸防炮要中 3 发才沉；deck 是车底的高度
  G.LCAC = LCAC
  -- 车底在 base 时气垫艇的 CFrame：车停在艇的后半（往后 2 格），艇和车同一朝向
  --   冲上沙滩时艇跟着地面抬高（一层气垫托着），不陷进沙里
  local function lcacUnder(base)
    local look = V(base.LookVector.X, 0, base.LookVector.Z)
    look = (look.Magnitude > 0.01) and look.Unit or V(0, 0, -1)
    local g = Map.ground(base.Position.X, base.Position.Z)
    local p = V(base.Position.X, g + LCAC.y, base.Position.Z) + look * 2
    return CFrame.lookAt(p, p + look)
  end
  local function carryOn(veh, base)
    local boat = G.newEnt({ kind = "lcac", team = veh.team, cat = "ship", hp = LCAC.hp, size = LCAC.size, cf = lcacUnder(base), extra = { sea = true } })
    boat.veh, boat.state = veh, "carry"
    veh.lcac = boat
    veh.model:SetAttribute("Lcac", true)
    boat.model:SetAttribute("Carry", veh.id)   -- 客户端：开这辆车的人本地按自己的车摆这条艇（Drive.lua G.lcacUnderMine）
    boat.onDeath = function(self, src)
      if self.veh and self.veh.alive and self.veh.lcac == self then G.damageEnt(self.veh, 1e6, src) end   -- 艇沉了，车也没了
      self.state = "sunk"
      task.delay(3, function() G.removeEnt(self) end)
    end
    table.insert(lcacs, boat)
  end
  -- 车开上岸了：气垫艇放下车，停一会儿自己回去（收走）
  G.lcacUnder, G.lcacCarry = lcacUnder, carryOn
  local function dropOff(veh)
    local boat = veh.lcac
    veh.lcac = nil
    veh.model:SetAttribute("Lcac", false)
    if boat and boat.model then boat.model:SetAttribute("Carry", nil) end
    if boat and boat.alive then boat.veh, boat.state, boat.backAt = nil, "landed", now() + 8 end
  end
  G.lcacDropOff = dropOff
  local function stepLcacs(dt)
    for i = #lcacs, 1, -1 do
      local boat = lcacs[i]
      if not boat.alive then
        table.remove(lcacs, i)
      elseif boat.state == "carry" then
        local veh = boat.veh
        if not veh or not veh.alive or veh.lcac ~= boat then   -- 车被打爆、没人开收走了：艇也收走
          G.removeEnt(boat)
          table.remove(lcacs, i)
        end
      elseif boat.state == "landed" and now() >= boat.backAt then
        G.removeEnt(boat)
        table.remove(lcacs, i)
      end
    end
  end

  ---------------------------------------------------------------- 生成点（Depots.lua）摆一辆空车

  -- 陆地上停在地台上；登陆平台外的水面上站在气垫艇上（两栖车也坐艇：自己游太慢，三千多格要好几分钟）
  --   生成的人 30 秒内独占（别人上不去）；没人上 90 秒收走（不算冷却）
  function G.spawnGroundVeh(team, id, base, sea, P)
    local d = VD.get(id)
    if not d then return nil end
    local face = V(base.LookVector.X, 0, base.LookVector.Z)
    if face.Magnitude < 0.01 then face = V(0, 0, -1) end
    face = face.Unit
    local p = base.Position
    local e
    if sea then
      local b = CFrame.lookAt(V(p.X, LCAC.deck, p.Z), V(p.X, LCAC.deck, p.Z) + face)
      e = newVehicle(team, id, b)
      carryOn(e, b)
    else
      e = newVehicle(team, id, baseAt(d, p.X, p.Z, face))
    end
    e.emptyAt = now()
    e.resP, e.resUntil = P, now() + 30
    return e
  end

  -- 刚生成的车 / 飞机 30 秒内只给生成的人（他还活着、还在服务器里）；别人上就说一声
  function G.reservedFor(e, P)
    local R = e.resP
    if R and R ~= P and now() < (e.resUntil or 0) and R.alive and G.P[R.pl] == R then
      G.msg(P.pl, "bad", "ui.reserved")
      return true
    end
    return false
  end

  -- 上自己队的空车（离车 18 格以内）
  function G.ACT.enterVeh(P, entId)
    local e = type(entId) == "string" and G.entById[entId] or nil
    if not e or not e.alive or not e.def or e.driver or e.ai or e.team ~= P.team or P.vehicle or not P.alive or not P.char then return end   -- AI 开着的上不去
    if G.reservedFor(e, P) then return end
    local hrp = P.char:FindFirstChild("HumanoidRootPart")
    if not hrp or (hrp.Position - e.root.CFrame.Position).Magnitude > e.def.L * 0.5 + 18 then return end
    e.resP = nil
    seat(P, e)
  end

  ---------------------------------------------------------------- 开车、开火、烟幕弹（客户端发来的）

  local function src(P) return { P = P, team = P.team, name = P.pl.DisplayName } end
  local function spreadDir(dir, deg)
    if not deg or deg <= 0 then return dir end
    local s = math.rad(deg)
    return (dir + V((math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s)).Unit
  end

  local function sync(P, e, d)
    if e.locked then return end
    local cf = d.cf
    if typeof(cf) ~= "CFrame" then return end
    local t = now()
    local dt = math.max(0.02, t - (e.lastSync or t))
    local p0, p1 = e.root.CFrame.Position, cf.Position
    local flat = V(p1.X - p0.X, 0, p1.Z - p0.Z).Magnitude
    local maxD = math.max(e.def.speed, e.lcac and LCAC.speed or 0) * 1.5 * dt + 6
    local h = Map.height(p1.X, p1.Z)
    local bad = flat > maxD or p1.Y ~= p1.Y or math.abs(p1.Y - math.max(h, -e.def.H) - e.def.H / 2) > e.def.H * 1.5 + 6
    if not e.def.amphib and h < -3 and not e.lcac then bad = true end
    if math.abs(p1.X) > Map.R or math.abs(p1.Z) > Map.R then bad = true end
    e.lastSync = t
    if bad then
      e.bad = (e.bad or 0) + 1
      G.R.Drive:FireClient(P.pl, { op = "fix", cf = e.root.CFrame })
      return
    end
    G.moveEnt(e, cf)
    if e.lcac then   -- 站在气垫艇上：艇跟着车走；开上岸了把车放下
      if e.lcac.alive then G.moveEnt(e.lcac, lcacUnder(cf * CF(0, -e.def.H / 2, 0))) end
      if h > 0.8 then dropOff(e) end
    end
    local d0 = e.def
    if type(d.ty) == "number" and d.ty == d.ty then e.ty = d.ty % 360 end
    if type(d.gp) == "number" and d.gp == d.gp then e.gp = math.clamp(d.gp, d0.turret.elev[1], d0.turret.elev[2]) end
    e.model:SetAttribute("Ty", math.floor(e.ty * 2 + 0.5) / 2)
    e.model:SetAttribute("Gp", math.floor(e.gp * 2 + 0.5) / 2)
    if type(d.sp) == "number" then e.model:SetAttribute("Sp", math.floor(math.clamp(d.sp, -99, 99) + 0.5)) end
    if d0.rws then   -- 遥控武器站的转角（别人那边的机枪塔跟着转）
      if type(d.my) == "number" and d.my == d.my then e.my = (d.my + 180) % 360 - 180 end
      if type(d.mp) == "number" and d.mp == d.mp then e.mp = math.clamp(d.mp, d0.rws.elev[1], d0.rws.elev[2]) end
      e.model:SetAttribute("My", math.floor((e.my or 0) * 2 + 0.5) / 2)
      e.model:SetAttribute("Mp", math.floor((e.mp or 0) * 2 + 0.5) / 2)
    end
  end

  local function angDiff(a, b) return (a - b + 180) % 360 - 180 end

  -- 开火那一刻客户端的炮塔、炮管、机枪塔角度（用户：弹道要顺着枪管和炮管、开火位置和枪口对上）：
  --   客户端每秒才报十来次角度，炮塔一转服务器记的就落后几度——开火时把这一刻的角度一起发来，和服务器记的差得不多才用（防作弊）
  local function fireAngles(e, m)
    if type(m) ~= "table" then return end
    local d0 = e.def
    local function num(x) return type(x) == "number" and x == x end
    if num(m.ty) and math.abs(angDiff(m.ty, e.ty)) < 25 then e.ty = m.ty % 360 end
    if num(m.gp) and math.abs(m.gp - e.gp) < 15 then e.gp = math.clamp(m.gp, d0.turret.elev[1], d0.turret.elev[2]) end
    if d0.rws then
      if num(m.my) and math.abs(angDiff(m.my, e.my or 0)) < 40 then e.my = (m.my + 180) % 360 - 180 end
      if num(m.mp) and math.abs(m.mp - (e.mp or 0)) < 30 then e.mp = math.clamp(m.mp, d0.rws.elev[1], d0.rws.elev[2]) end
    end
  end

  local function fire(P, e, wid, dir, aim, msg)
    if G.round.phase ~= "battle" or e.locked then return end
    local d = e.def
    if type(wid) ~= "string" or not table.find(d.weapons, wid) then return end
    local w = VD.W[wid]
    local st = e.wst[wid]
    local t = now()
    if t < st.next then return end
    if st.mag <= 0 then
      if st.reserve <= 0 then return end
      local n = math.min(w.mag, st.reserve)
      st.mag, st.reserve = n, st.reserve - n
    end
    local base = baseOf(e)
    fireAngles(e, msg)
    local mz = VD.muzzle(d, base, e.ty, e.gp, VD.mgWhich(d, wid), e.my, e.mp)
    local gdir = mz.LookVector   -- 顺着炮管 / 枪管出去（原来客户端给的方向和炮管差 8° 以内就用客户端的，弹道会斜着出炮口）
    local S = src(P)
    if w.kind == "shell" then
      G.launch({ kind = "shell", pos = mz.Position, vel = gdir * w.speed, grav = true, gscale = w.drop / 0.55, w = w, src = S, ignore = { e.model, P.char },
        life = w.range / w.speed + 0.5 })
      G.fx({ k = "vfire", p = mz.Position, d = gdir, f = w.fx, id = e.id })
    elseif w.kind == "gun" then
      G.botShot(mz.Position, mz.Position + spreadDir(gdir, w.spread) * w.range, w, S, { e.model, P.char }, 0)
    elseif w.kind == "arty" then
      if typeof(aim) ~= "Vector3" then return end
      local flat = V(aim.X - mz.Position.X, 0, aim.Z - mz.Position.Z)
      local dist = flat.Magnitude
      if dist < w.minR or dist > w.maxR then G.msg(P.pl, "bad", "ui.outOfRange") return end
      local sc = (w.scatter or 10) + dist * 0.01
      local a, r = math.random() * math.pi * 2, math.random() * sc
      local x, z = aim.X + math.cos(a) * r, aim.Z + math.sin(a) * r
      G.shell(V(x, Map.ground(x, z), z), w, S, w.flight + dist / 700, mz.Position)
      G.fx({ k = "vfire", p = mz.Position, d = gdir, f = "arty", id = e.id })
    end
    st.mag -= 1
    st.next = t + w.rate
    if st.mag <= 0 and st.reserve > 0 then   -- 弹匣打空：换弹
      local n = math.min(w.mag, st.reserve)
      st.mag, st.reserve = n, st.reserve - n
      st.next = t + math.max(w.rate, w.reload or 0)
    end
  end

  -- 烟幕：G.smokes = { { p, r, t0, t1 } }
  local smokes = {}
  G.smokes = smokes
  local function smokeR(s, t)
    if t >= s.t1 or t < s.t0 then return 0 end
    local grow = math.clamp((t - s.t0) / 2.5, 0.25, 1)
    local fade = math.clamp((s.t1 - t) / 6, 0, 1)
    return s.r * grow * (0.4 + 0.6 * fade)
  end
  -- 线段 a→b 有没有穿过烟团
  function G.smokeBlocks(a, b)
    if #smokes == 0 then return false end
    local t = now()
    local ab = b - a
    local L2 = ab:Dot(ab)
    for i = #smokes, 1, -1 do
      local s = smokes[i]
      if t >= s.t1 then
        table.remove(smokes, i)
      else
        local r = smokeR(s, t)
        if r > 0 then
          local k = (L2 > 0) and math.clamp((s.p - a):Dot(ab) / L2, 0, 1) or 0
          if (a + ab * k - s.p).Magnitude < r * 0.85 then return true end
        end
      end
    end
    return false
  end

  local function smoke(P, e)
    local t = now()
    if e.locked or e.smokeLeft <= 0 or t < e.smokeNext then return end
    e.smokeLeft -= 1
    e.smokeNext = t + SM.reload
    local tubes = VD.smokeTubes(e.def, baseOf(e), e.ty)
    local list = {}
    for _, tb in ipairs(tubes) do
      local flat = V(tb.dir.X, 0, tb.dir.Z)
      flat = (flat.Magnitude > 0.01) and flat.Unit or V(0, 0, -1)
      local L = SM.range * (0.85 + math.random() * 0.3)
      local x, z = tb.pos.X + flat.X * L, tb.pos.Z + flat.Z * L
      local y = math.max(Map.ground(x, z), 0) + 2.5
      table.insert(list, { a = tb.pos, b = V(x, y, z) })
    end
    G.fx({ k = "smokeLaunch", id = e.id, list = list })
    task.delay(0.9, function()
      for _, it in ipairs(list) do
        table.insert(smokes, { p = it.b, r = SM.r, t0 = now(), t1 = now() + SM.life })
        G.fx({ k = "smokeCloud", p = it.b, r = SM.r, life = SM.life })
      end
    end)
    G.pushOne(P)
  end

  function G.driveInput(P, d)
    local e = P.vehicle
    if not e or not e.alive or e.driver ~= P or type(d) ~= "table" then return end
    if d.op == "state" then sync(P, e, d)
    elseif d.op == "fire" then fire(P, e, d.w, d.dir, d.aim, d)
    elseif d.op == "smoke" then smoke(P, e)
    elseif d.op == "exit" then unseat(P, e, true) end
  end

  ---------------------------------------------------------------- 每帧：车组跟着车走；空车放久了收走

  G.onFrame(function(dt)
    stepLcacs(dt)
    local t = now()
    for _, e in ipairs(table.clone(vehicles)) do
      local D = e.driver
      if D then
        if not D.alive or not D.char or not D.char.Parent or G.P[D.pl] ~= D then
          e.driver = nil
          e.emptyAt = t
          e.model:SetAttribute("Driver", 0)
        else
          D.char:PivotTo(e.root.CFrame)
        end
      elseif e.alive and e.emptyAt and t - e.emptyAt > 90 then   -- 没人开 90 秒：收走（不算冷却）
        for i, x in ipairs(vehicles) do
          if x == e then table.remove(vehicles, i) break end
        end
        if e.lcac then G.removeEnt(e.lcac) end
        G.removeEnt(e)
      end
    end
  end)

  -- 给客户端的：自己的车（弹药、烟幕弹）、名额
  function G.vehState(P)
    local e = P.vehicle
    if not e or not e.alive then return nil end
    local ammo = {}
    for wid, st in pairs(e.wst) do ammo[wid] = { st.mag, st.reserve } end
    return { id = e.id, m = e.def.id, locked = e.locked or false, smoke = e.smokeLeft, ammo = ammo }
  end

  G.on("died", function(P)
    local e = P.vehicle
    if e then unseat(P, e, false) end
  end)
  G.on("left", function(P)
    local e = P.vehicle
    if e then unseat(P, e, false) end
  end)
  G.on("roundStart", function()
    for _, e in ipairs(vehicles) do G.removeEnt(e) end
    for _, b in ipairs(lcacs) do G.removeEnt(b) end
    vehicles, lcacs = {}, {}
    G.vehicles = vehicles
    pending = { atk = {}, def = {} }
    table.clear(smokes)
    for _, P in pairs(G.P) do P.vehicle = nil end
  end)
end

return Armor
