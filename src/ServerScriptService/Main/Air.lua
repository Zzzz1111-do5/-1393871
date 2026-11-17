-- Roblox全面大战场——飞机、直升机（服务器）：生成（名额、挂载）、飞行同步（位置由开飞机的客户端算，服务器查速度、查撞地）、
--   航炮（扣着扳机按射速连发）、空空 / 空地导弹（比例导引、过载有限、近炸引信；热诱弹骗走红外弹）、炸弹（制导的往目标滑）、火箭巢、
--   跳伞（固定翼弹射、直升机高处跳伞）、没人开的飞机掉下来、撞地 / 坠海、落在自己的机场 / 甲板上补弹修理、运输直升机载人
--   生成点在地图里（Depots.lua）：攻方直升机在两栖攻击舰甲板、固定翼在航母（舰载机）和攻方机场岛；
--     守方直升机在营地、固定翼在主岛机场（据点 D 还在手里时）；生成后停在那里，自己走过去按 E 坐上
local RS = game:GetService("ReplicatedStorage")

local Air = {}

function Air.init(G)
  local Config, Map = G.Config, G.Map
  local AD = require(RS:WaitForChild("AirDefs"))
  local V = Vector3.new
  local CF = CFrame.new
  local now = os.clock
  local CATS = Config.VehicleCats
  local AIRCATS = { heli = true, jet = true }
  local GRAV = AD.GRAV

  local aircraft = {}
  local pending = { atk = {}, def = {} }   -- 被毁的占着名额：[cat] = { 冷却到什么时候 }
  G.aircraft = aircraft

  ---------------------------------------------------------------- 地面（含甲板）

  -- (x, z) 处能落地的面多高：地形、甲板
  local function surface(x, z) return AD.ground(Map, x, z) end
  G.airSurface = surface

  ---------------------------------------------------------------- 名额

  local function used(team, cat)
    local n = 0
    for _, e in ipairs(aircraft) do if e.alive and e.team == team and e.vcat == cat then n += 1 end end
    local t = now()
    local list = pending[team][cat] or {}
    for i = #list, 1, -1 do if list[i] <= t then table.remove(list, i) else n += 1 end end
    pending[team][cat] = list
    return n
  end
  local function avail(team)
    local out = {}
    local tn = G.teamCount(team)
    for cat in pairs(AIRCATS) do
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
  -- 接到地面载具的名额、型号表上
  local vehAvail0, vehModels0 = G.vehAvail, G.vehModels
  function G.vehAvail(team)
    local out = vehAvail0 and vehAvail0(team) or {}
    for k, v in pairs(avail(team)) do out[k] = v end
    return out
  end
  function G.vehModels(team)
    local out = vehModels0 and vehModels0(team) or {}
    for _, cat in ipairs(Config.VehicleOrder) do
      if AIRCATS[cat] then
        for _, id in ipairs(Config.Vehicles[team][cat] or {}) do if AD.get(id) then table.insert(out, id) end end
      end
    end
    return out
  end

  ---------------------------------------------------------------- 出生点

  local function deckOf(kind)
    for _, d in ipairs(G.decks or {}) do if d.kind == kind then return d end end
    return nil
  end
  local function pointOk(team, id)
    local s = G.points and G.points[id]
    return s and s.owner == team and not (team == "def" and s.pressed)
  end
  ---------------------------------------------------------------- 挂载（每个挂点剩几枚）

  local function storesStr(e)
    local s = {}
    for i, n in ipairs(e.stores) do s[i] = string.char(48 + math.clamp(n, 0, 40)) end   -- '0' 起（40 枚以内一个字符）
    return table.concat(s)
  end
  local function loadStr(e)
    local s = {}
    for i, w in ipairs(e.load) do s[i] = w or "" end
    return table.concat(s, ",")
  end
  -- 油量（用户：增加油量这个东西、可以挂副油箱）：e.fuel 内油、e.fuelX 副油箱里还有的油（都按「内油加满 = 1」算），
  --   属性 Fuel / FuelX 给客户端的油量表和熄火用（往上取整到 0.2%：只有真烧干了才是 0）
  local function pushFuel(e)
    local m = e.model
    local f = math.ceil(math.max(0, e.fuel or 0) * 500) / 500
    local x = math.ceil(math.max(0, e.fuelX or 0) * 500) / 500
    if m:GetAttribute("Fuel") ~= f then m:SetAttribute("Fuel", f) end
    if m:GetAttribute("FuelX") ~= x then m:SetAttribute("FuelX", x) end
  end
  local function fillStores(e)
    local d = e.def
    e.stores = {}
    for i, s in ipairs(d.st or {}) do
      local w = e.load[i]
      e.stores[i] = w and AD.count(s, w) or 0
    end
    e.gunAmmo = d.gunAmmo
    e.flares = d.flares
    e.fuelX = (AD.tankFuel(d, e.load))   -- 副油箱挂回去、加满
    e.model:SetAttribute("Stores", storesStr(e))
    e.model:SetAttribute("Flares", e.flares)
    pushFuel(e)
  end

  ---------------------------------------------------------------- 上下飞机

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
  -- 战术平板（遥控无人机）：胸前端着一块加固平板（橡胶包角、天线、屏幕亮着），两条胳膊抬起来托着；别人看得到这个人在遥控
  --   （用户：无人机驾驶应该是用一个战术平板）。胳膊靠改肩、肘关节的 C0（动画的 Transform 叠在上面，原来的 C0 记在 P.armC0 里，收起时还原）
  local TAB = { body = Color3.fromRGB(46, 50, 44), bump = Color3.fromRGB(24, 26, 24), scr = Color3.fromRGB(64, 118, 150), bez = Color3.fromRGB(16, 18, 18) }
  local ARM = {
    RightShoulder = CFrame.Angles(math.rad(20), 0, math.rad(-14)), LeftShoulder = CFrame.Angles(math.rad(20), 0, math.rad(14)),   -- R15：大臂往前、往里收
    RightElbow = CFrame.Angles(math.rad(85), 0, 0), LeftElbow = CFrame.Angles(math.rad(85), 0, 0),                                  -- 小臂往前抬平
    ["Right Shoulder"] = CFrame.Angles(0, 0, math.rad(62)), ["Left Shoulder"] = CFrame.Angles(0, 0, math.rad(-62)),                  -- R6：整条胳膊往前抬
  }
  local function tablet(P, on)
    local char = P.char
    if not char then return end
    local old = char:FindFirstChild("UavTablet")
    if old then old:Destroy() end
    for j, c0 in pairs(P.armC0 or {}) do
      if j.Parent then j.C0 = c0 end
    end
    P.armC0 = nil
    char:SetAttribute("Tablet", on == true)
    if not on then return end
    local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
    if not torso then return end
    P.armC0 = {}
    for _, j in ipairs(char:GetDescendants()) do
      if j:IsA("Motor6D") and ARM[j.Name] then
        P.armC0[j] = j.C0
        j.C0 = j.C0 * ARM[j.Name]
      end
    end
    local m = Instance.new("Model")
    m.Name = "UavTablet"
    local k = math.max(torso.Size.X, 1) / 2   -- 按上身宽缩放（R15、R6 上身都是 2 格宽）
    -- 平板在肚子前面、上沿往外倾 50°，屏幕（+Z 面）朝着脸
    local base = torso.CFrame * CF(0, -0.3 * k, -1.25 * k) * CFrame.Angles(math.rad(-50), 0, 0)
    local function piece(name, size, off, col, mat, shape, rot)
      local p = Instance.new("Part")
      p.Name = name
      if shape then p.Shape = shape end
      p.Size = size * k
      p.Color = col
      p.Material = mat or Enum.Material.SmoothPlastic
      p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = false, false, false, true, false
      p.CFrame = base * CF(off.X * k, off.Y * k, off.Z * k) * (rot or CF())   -- 先摆好再焊（焊上以后改 CFrame 会把整个人拖过去）
      local w = Instance.new("WeldConstraint")
      w.Part0, w.Part1 = torso, p
      w.Parent = p
      p.Parent = m
      return p
    end
    piece("Body", V(1.3, 0.88, 0.1), V(), TAB.body)
    piece("Bezel", V(1.16, 0.72, 0.012), V(0, 0.01, 0.054), TAB.bez)
    local scr = piece("Screen", V(1.04, 0.62, 0.01), V(0, 0.02, 0.062), TAB.scr, Enum.Material.Neon)
    scr.Transparency = 0.15
    for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do   -- 四个橡胶包角
      piece("Bumper", V(0.2, 0.2, 0.15), V(c[1] * 0.6, c[2] * 0.39, 0), TAB.bump, Enum.Material.Rubber)
    end
    piece("Grip", V(0.1, 0.5, 0.16), V(-0.68, 0, -0.02), TAB.bump, Enum.Material.Rubber)
    piece("Grip", V(0.1, 0.5, 0.16), V(0.68, 0, -0.02), TAB.bump, Enum.Material.Rubber)
    piece("Antenna", V(0.36, 0.05, 0.05), V(0.52, 0.56, -0.03), TAB.bump, Enum.Material.Rubber, Enum.PartType.Cylinder, CFrame.Angles(0, 0, math.pi / 2))   -- 数据链天线竖在右上角
    piece("Led", V(0.035, 0.035, 0.02), V(-0.5, 0.4, 0.06), Color3.fromRGB(90, 255, 120), Enum.Material.Neon)
    m.Parent = char
  end
  G.uavTablet = tablet

  local function seat(P, e, asPass)
    local char = P.char
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.Anchored = true end
    -- 无人机：人站在原地拿平板遥控（不藏、不挪进机身，照样会挨打）；P.remote 记着遥控的是哪架（G.inVeh 不把他算在载具里）
    local uav = e.def.drone and not asPass
    if uav then tablet(P, true) else hideChar(char, true) end
    P.vehicle = e
    P.remote = uav and e or nil
    if asPass then
      table.insert(e.pass, P)
    else
      e.driver = P
      e.emptyAt = nil
      e.model:SetAttribute("Driver", P.pl.UserId)
      if uav then
        e.loit = nil
        e.opId = P.pl.UserId
        e.model:SetAttribute("Op", P.pl.UserId)
        e.model:SetAttribute("Loiter", false)
      end
    end
    if not uav then char:PivotTo(e.root.CFrame) end
    G.pushOne(P)
  end
  -- 无人机断了链路（收起平板、操作员阵亡 / 走了）：在天上的照原来的高度自动盘旋 LOITER 秒（等操作员重连，ACT.uavLink），时间到了才掉下来
  local LOITER = 75
  local function startLoiter(e)
    if not e.alive or not e.def.drone or e.onGround then return end
    local cf = e.root.CFrame
    local h = V(cf.LookVector.X, 0, cf.LookVector.Z)
    h = (h.Magnitude > 0.05) and h.Unit or V(0, 0, -1)
    local r = V(-h.Z, 0, h.X)   -- 右边（往右盘旋）
    local R = math.max(e.def.W * 8, 380)
    local p = cf.Position
    local c = p + r * R
    e.loit = { c = c, r = R, a = math.atan2(p.Z - c.Z, p.X - c.X), v = math.max(e.def.stall * 1.25, e.def.vMil * 0.55), y = p.Y, T = now() + LOITER }
    e.model:SetAttribute("Loiter", true)
    e.model:SetAttribute("LoitEnd", workspace:GetServerTimeNow() + LOITER)   -- 客户端提示还剩几秒
  end
  local function loiterStep(e, dt)
    local L = e.loit
    L.a += L.v / L.r * dt
    local x, z = L.c.X + math.cos(L.a) * L.r, L.c.Z + math.sin(L.a) * L.r
    local y = math.max(L.y, math.max(surface(x, z), 0) + e.def.gearH + 120)   -- 盘旋圈上有山：抬高一点绕过去
    L.y = L.y + (y - L.y) * math.min(1, dt * 0.5)
    local np = V(x, L.y, z)
    local tang = V(-math.sin(L.a), 0, math.cos(L.a))
    e.vel = tang * L.v
    G.moveEnt(e, CFrame.lookAt(np, np + tang) * CFrame.Angles(0, 0, -math.rad(16)))
  end

  -- 下飞机：在地上走到机身旁边；在天上跳伞（固定翼是弹射座椅：往上弹出去）
  local function unseat(P, e, place)
    if P.vehicle == e then P.vehicle = nil end
    local uav = P.remote == e
    if uav then P.remote = nil end
    if e.driver == P then
      e.driver = nil
      e.emptyAt = now()
      e.trig = false
      e.model:SetAttribute("Driver", 0)
      e.model:SetAttribute("Fire", false)
      if e.def.drone then startLoiter(e) end
    end
    for i, Q in ipairs(e.pass) do if Q == P then table.remove(e.pass, i) break end end
    local char = P.char
    if uav then   -- 遥控无人机的：人本来就在地上，收起平板就行
      tablet(P, false)
      local hrp = char and char:FindFirstChild("HumanoidRootPart")
      if hrp and char.Parent then hrp.Anchored = false end
      G.pushOne(P)
      return
    end
    if char and char.Parent and place then
      hideChar(char, false)
      local hrp = char:FindFirstChild("HumanoidRootPart")
      local cf = e.root.CFrame
      local p = cf.Position
      local agl = p.Y - math.max(surface(p.X, p.Z), 0) - e.def.gearH
      if hrp then hrp.Anchored = false end
      if agl > 25 then   -- 天上：跳伞
        local up = (e.def.kind == "jet") and 30 or 0
        local out = (e.def.kind == "jet") and (cf * CF(0, e.def.H * 0.5 + 8 + up, 0)).Position or (cf * CF(e.def.W * 0.5 + 6, -2, 0)).Position
        char:PivotTo(CFrame.lookAt(out, out + cf.LookVector))
        if hrp then hrp.AssemblyLinearVelocity = (e.vel or V()) * 0.25 + V(0, (e.def.kind == "jet") and 20 or 0, 0) end
        P.chute = now()
        char:SetAttribute("Chute", true)
        if e.def.kind == "jet" then G.fx({ k = "eject", p = (cf * CF(0, e.def.H * 0.4, e.def.canopy and e.def.canopy.z or 0)).Position, id = e.id }) end
      else
        local side = cf * CF(-(e.def.W * 0.5 + 5), 0, 0)
        local x, z = side.Position.X, side.Position.Z
        local y = math.max(surface(x, z), 0) + 3.5
        char:PivotTo(CFrame.lookAt(V(x, y, z), V(x, y, z) + V(cf.LookVector.X, 0, cf.LookVector.Z)))
      end
    end
    G.pushOne(P)
  end

  ---------------------------------------------------------------- 新飞机、被毁

  local function newAircraft(team, id, cf, P, load, vel, onGround, fuel)
    local d = AD.get(id)
    local hp = math.floor(d.hp * ((Config.VehicleMod[id] and Config.VehicleMod[id].hp) or 1))
    local e = G.newEnt({ kind = "air", team = team, cat = "air", hp = hp, size = d.hitbox, cf = cf, air = true, solid = true,   -- 实心：停着的飞机人穿不过去
      extra = { def = d, vcat = d.cat } })
    e.model:SetAttribute("Model", id)
    e.model:SetAttribute("Driver", 0)
    e.load = AD.cleanLoad(d, load)
    e.model:SetAttribute("Load", loadStr(e))
    e.fuelSel = AD.cleanFuel(fuel)   -- 出发时选的内油（落地加油也加到这么多）
    e.fuel = e.fuelSel
    fillStores(e)
    e.vel = vel or V()
    e.onGround = onGround
    e.pass = {}
    e.lastSync = now()
    e.gunT = 0
    e.trig = false
    e.aim = nil
    e.bay = 0
    e.model:SetAttribute("Gear", onGround and 1 or 0)
    e.model:SetAttribute("Thr", onGround and 0 or 80)
    e.model:SetAttribute("Rpm", onGround and 0 or 100)
    e.onDeath = function(self, src)
      G.try("飞机被毁", function()
        self.alive = false
        self.wreck = true
        self.model:SetAttribute("Wreck", true)
        G.fx({ k = "boom", p = self.root.CFrame.Position, s = 2.6, c = "wreck" })
        G.fx({ k = "airWreck", id = self.id, p = self.root.CFrame.Position, v = self.vel or V() })
        local list = pending[self.team][self.vcat] or {}
        table.insert(list, now() + (CATS[self.vcat].cd or 75))
        pending[self.team][self.vcat] = list
        local function kill(Q)
          Q.vehicle = nil
          if Q.char then
            hideChar(Q.char, false)
            G.hurtChar(Q.char, 1e5, src)
          end
          G.msg(Q.pl, "bad", "ui.vehLost")
        end
        local D = self.driver
        if D and D.remote == self then   -- 无人机被打掉：操作员在地上，只是断了链路
          unseat(D, self, true)
          G.msg(D.pl, "bad", "ui.uavLost")
          D = nil
        end
        self.driver = nil
        if D then kill(D) end
        for _, Q in ipairs(self.pass) do kill(Q) end
        self.pass = {}
        if src and src.P and G.P[src.P.pl] == src.P then G.msg(src.P.pl, "kill", "ui.vehKilled", { k = "veh." .. self.def.id }) end
        for i, x in ipairs(aircraft) do if x == self then table.remove(aircraft, i) break end end
      end)
      task.delay(4, function() G.removeEnt(self) end)
    end
    table.insert(aircraft, e)
    return e
  end

  ---------------------------------------------------------------- 生成点（Depots.lua）摆一架空飞机

  -- 停在停机位上（cf 是机身中心：地面 / 甲板 + 起落架高），挂载照挂载界面选的（没给就按第一套预设）；
  --   生成的人 30 秒内独占；没人上 90 秒收走（不算冷却）
  function G.spawnAircraft(team, id, cf, load, P, fuel)
    local d = AD.get(id)
    if not d then return nil end
    local e = newAircraft(team, id, cf, nil, (type(load) == "table") and load or AD.presetLoad(d), V(), true, fuel)
    e.home = "pad"
    e.emptyAt = now()
    e.resP, e.resUntil = P, now() + 30
    if d.drone and P and P.alive and P.char and not P.vehicle and G.P[P.pl] == P then   -- 无人机：在终端前直接拿出平板接管，不用走到跑道上
      e.resP = nil
      seat(P, e)
    end
    return e
  end

  -- 上飞机：自己队的、离机身够近；有人开的运输直升机还有空座就坐后面
  local enter0 = G.ACT.enterVeh
  G.ACT.enterVeh = function(P, entId)
    local e = type(entId) == "string" and G.entById[entId] or nil
    if not e or not e.air then
      if enter0 then return enter0(P, entId) end
      return
    end
    if not e.alive or e.team ~= P.team or P.vehicle or not P.alive or not P.char then return end
    if not e.driver and G.reservedFor and G.reservedFor(e, P) then return end
    local hrp = P.char:FindFirstChild("HumanoidRootPart")
    if not hrp or (hrp.Position - e.root.CFrame.Position).Magnitude > math.max(e.def.L, e.def.W) * 0.5 + 18 then return end
    if not e.driver then e.resP = nil seat(P, e) return end
    if e.def.transport and #e.pass < (e.def.seats or 1) then seat(P, e, true) end
  end
  -- 重连自己放出去的无人机（收起平板、操作员阵亡后它在原地盘旋；停在地上的也行）：在哪都能连，不用走到飞机旁边
  G.ACT.uavLink = function(P, entId)
    local e = type(entId) == "string" and G.entById[entId] or nil
    if not e or not e.air or not e.alive or not e.def.drone or e.driver or e.team ~= P.team then return end
    if e.opId ~= P.pl.UserId or P.vehicle or not P.alive or not P.char then return end
    seat(P, e)
  end

  ---------------------------------------------------------------- 武器

  local function src(P) return P and { P = P, team = P.team, name = P.pl.DisplayName } or nil end
  local function ignoreOf(e)
    local list = { e.model }
    if e.driver and e.driver.char then table.insert(list, e.driver.char) end
    for _, Q in ipairs(e.pass) do if Q.char then table.insert(list, Q.char) end end
    return list
  end
  local function turnToward(dir, want, maxA)
    local c = math.clamp(dir:Dot(want), -1, 1)
    local a = math.acos(c)
    if a <= maxA or a < 1e-4 then return want end
    local axis = dir:Cross(want)
    if axis.Magnitude < 1e-6 then axis = (math.abs(dir.Y) < 0.9) and dir:Cross(V(0, 1, 0)) or dir:Cross(V(1, 0, 0)) end
    return (CFrame.fromAxisAngle(axis.Unit, maxA) * dir).Unit
  end
  local function tgtPos(t)
    if not t then return nil end
    if t.decoy then return t.pos end
    if t.alive and t.root and t.root.Parent then return t.root.CFrame.Position end
    return nil
  end
  local function tgtVel(t)
    if t and t.decoy then return t.vel end
    return (t and t.vel) or V()
  end

  -- 导弹：助推到额定速度、之后慢慢减速；比例导引（带提前量）、过载有限；导引头看不到目标就丢失；近炸
  local function guideMissile(s, dt)
    s.age += dt
    local w = s.w
    local spd = s.vel.Magnitude
    if s.age < (w.burn or 3) then spd = math.min(w.speed, spd + w.speed * 1.4 * dt)
    else spd = math.max(w.speed * 0.3, spd - w.speed * 0.12 * dt) end
    local dir = s.vel.Unit
    local t = s.tgt
    if t and t.decoy then t.pos += t.vel * dt t.vel += V(0, -GRAV * 0.4, 0) * dt end
    local tp = tgtPos(t)
    if not tp then
      s.tgt, t = nil, nil
      tp = s.aimPt
    end
    if tp then
      local rel = tp - s.pos
      local dist = rel.Magnitude
      local tgo = dist / math.max(spd, 1)
      local lead = tp + tgtVel(t) * math.min(tgo, 4) * 0.95
      local want = (lead - s.pos).Unit
      if dir:Dot(want) < math.cos(math.rad(75)) and s.age > 0.6 then   -- 导引头看不到了：丢失目标，直飞
        s.tgt, s.aimPt = nil, nil
      else
        local k = (s.age < 0.25) and 0.4 or 1   -- 刚出架先稳一下
        dir = turnToward(dir, want, math.rad(w.turn) * dt * k)
      end
      local fuse = 8 + ((t and not t.decoy and t.root) and math.min(14, t.root.Size.Magnitude * 0.18) or 0)
      if dist < fuse then
        if t and t.decoy then G.fx({ k = "boom", p = s.pos, s = 0.6, c = "msl" }) return true end
        G.explode(s.pos, w, s.src)
        return true
      end
    end
    s.vel = dir * spd
    s.fixT = (s.fixT or 0) + dt
    if s.fixT > 0.3 then   -- 客户端画的弹按服务器的位置校一下
      s.fixT = 0
      G.fx({ k = "shotFix", id = s.id, p = s.pos, v = s.vel })
    end
    return false
  end
  -- 炸弹：真实重力；制导炸弹算还要多久落地，往目标方向改水平速度（带翼的滑得远）
  local function guideBomb(s, dt)
    s.age += dt
    s.vel += V(0, -GRAV, 0) * dt
    s.vel = s.vel * (1 - 0.02 * dt)
    local tp = tgtPos(s.tgt) or s.aimPt
    if s.w.guided and tp and s.age > 0.4 then
      local h = s.pos.Y - tp.Y
      local vy = -s.vel.Y
      local tFall = (vy + math.sqrt(math.max(0, vy * vy + 2 * GRAV * math.max(h, 0)))) / GRAV
      tFall = math.max(tFall, 0.3)
      local need = V(tp.X - s.pos.X, 0, tp.Z - s.pos.Z) / tFall
      local cur = V(s.vel.X, 0, s.vel.Z)
      local auth = (s.w.shape and s.w.shape.wing) and 40 or 26
      local dv = need - cur
      if dv.Magnitude > auth * dt then dv = dv.Unit * auth * dt end
      s.vel += dv
    end
    s.fixT = (s.fixT or 0) + dt
    if s.fixT > 0.4 then
      s.fixT = 0
      G.fx({ k = "shotFix", id = s.id, p = s.pos, v = s.vel })
    end
    return false
  end
  local function guideRocket(s, dt)
    s.age += dt
    s.vel += V(0, -GRAV * 0.25, 0) * dt
    return false
  end

  -- 挂点的世界位置
  local function stationWorld(e, s) return e.root.CFrame * CF(s.pos) end
  -- 选一个还有这种弹的挂点（左右交替）
  local function pickStation(e, wid)
    local d = e.def
    local best, bestN = nil, -1
    for i, s in ipairs(d.st or {}) do
      if e.load[i] == wid and e.stores[i] > 0 then
        -- 剩得最多的先用（左右轮流）；一样多的按顺序
        if e.stores[i] > bestN then best, bestN = i, e.stores[i] end
      end
    end
    return best
  end
  local function spend(e, i)
    e.stores[i] -= 1
    e.model:SetAttribute("Stores", storesStr(e))
  end
  -- 抛副油箱：auto 是油用完自动抛（挂着空箱子白白多阻力）；手动抛（J 键，进入空战前）里面剩的油一起扔掉
  local function dropTanks(e, auto)
    local any = false
    for i, s in ipairs(e.def.st or {}) do
      local wid = e.load[i]
      local w = wid and AD.W[wid]
      if w and w.kind == "tank" and (e.stores[i] or 0) > 0 then
        e.stores[i] = 0
        any = true
        G.fx({ k = "tankDrop", w = wid, cf = stationWorld(e, s), v = e.vel or V() })   -- 客户端：箱子翻着掉下去
      end
    end
    if not any then return false end
    e.fuelX = 0
    e.model:SetAttribute("Stores", storesStr(e))
    pushFuel(e)
    if e.driver then
      G.msg(e.driver.pl, "info", auto and "ui.tankEmpty" or "ui.tankDrop")
      G.pushOne(e.driver)
    end
    return true
  end
  -- 烧油：有人开的按他发来的油门 / 总距；链路断了自动盘旋的无人机按巡航；先烧副油箱（真飞机也是先用外挂的油），烧干了自动抛
  local function burnFuel(e, dt)
    local d, m = e.def, e.model
    local r
    if e.loit then
      r = AD.burn(d, 60, 0, 100, 0.6, false)
    elseif e.driver then
      local thr = (d.kind == "heli") and 100 or (m:GetAttribute("Thr") or 0)
      r = AD.burn(d, thr, m:GetAttribute("Col") or 0, m:GetAttribute("Rpm") or 0, (e.vel and e.vel.Magnitude or 0) / math.max(d.vMax, 1), e.onGround)
    else
      return
    end
    local use = r * dt
    if (e.fuelX or 0) > 0 then
      local take = math.min(e.fuelX, use)
      e.fuelX -= take
      use -= take
      if e.fuelX <= 1e-5 then dropTanks(e, true) end
    end
    if use > 0 then e.fuel = math.max(0, (e.fuel or 0) - use) end
    pushFuel(e)
  end

  -- 目标：客户端锁定的实体（服务器再看一眼：射程、导引头视场放宽一点）
  local function validTarget(e, w, tid)
    local t = (type(tid) == "string") and G.entById[tid] or nil
    if not t or not t.alive or t.team == e.team then return nil end
    local p0 = e.root.CFrame.Position
    local to = t.root.CFrame.Position - p0
    if to.Magnitude > (w.range or 3200) * 1.25 then return nil end   -- 炸弹没写射程
    if w.kind == "aam" and not t.air then return nil end
    if (w.kind == "agm" or w.kind == "bomb") and t.air then return nil end
    local fwd = e.root.CFrame.LookVector
    local cone = (w.kind == "bomb") and 75 or (w.cone * 1.6 + 6)
    if e.def.kind == "heli" and w.kind == "agm" then cone = cone + 20 end
    if w.kind ~= "bomb" and fwd:Dot(to.Unit) < math.cos(math.rad(cone)) then return nil end
    return t
  end

  local function fireStore(P, e, wid, tid, aim)
    local w = AD.W[type(wid) == "string" and wid or ""]
    if not w or w.kind == "gun" or w.kind == "tank" then return end   -- 副油箱不是弹（抛油箱走 jettison）
    if G.round.phase ~= "battle" then return end
    local t = now()
    if t < (e.nextStore or 0) then return end
    local i = pickStation(e, wid)
    if not i then return end
    local s = e.def.st[i]
    local scf = stationWorld(e, s)
    local fwd = e.root.CFrame.LookVector
    local S = src(P)
    local tgt = (w.kind == "aam" or w.kind == "agm" or w.kind == "bomb") and validTarget(e, w, tid) or nil
    local aimPt = (typeof(aim) == "Vector3" and aim.Magnitude < 1e6) and aim or nil
    local base = e.vel or V()
    if w.kind == "aam" or w.kind == "agm" then
      local launch = scf.Position - scf.UpVector * 1.2
      local sh = G.launch({ kind = "missile", pos = launch, vel = base + fwd * 60 - scf.UpVector * 6, w = w, src = S, ignore = ignoreOf(e), life = w.life or 8,
        step = guideMissile, age = 0, tgt = tgt, tgId = tgt and tgt.id or nil, aimPt = (not tgt and w.kind == "agm") and aimPt or nil, byEnt = e.id })
      e.nextStore = t + 0.35
      if tgt and tgt.driver then G.R.Drive:FireClient(tgt.driver.pl, { op = "rwr", id = sh.id, w = wid }) end
    elseif w.kind == "bomb" then
      G.launch({ kind = "bomb", pos = scf.Position - scf.UpVector * 1.5, vel = base - scf.UpVector * 4, w = w, src = S, ignore = ignoreOf(e), life = 30,
        step = guideBomb, age = 0, tgt = tgt, tgId = tgt and tgt.id or nil, aimPt = aimPt, byEnt = e.id })
      e.nextStore = t + ((e.def.bomber) and 0.12 or 0.25)
    elseif w.kind == "rkt" then
      local dir = (fwd + V((math.random() - 0.5) * 0.02, (math.random() - 0.5) * 0.02, (math.random() - 0.5) * 0.02)).Unit
      G.launch({ kind = "rocket", pos = scf.Position + fwd * 3, vel = base + dir * w.speed, w = w, src = S, ignore = ignoreOf(e), life = w.range / w.speed + 1,
        step = guideRocket, age = 0, byEnt = e.id })
      e.nextStore = t + w.rate
    end
    spend(e, i)
    G.fx({ k = "storeOff", id = e.id, st = i, w = wid })
  end

  -- 航炮：扣着扳机，每 0.1 秒打一发弹丸（带这 0.1 秒所有炮弹的伤害）；机头炮塔 / 舱门机枪朝准星（有转动范围）
  local function gunDir(e, w)
    local cf = e.root.CFrame
    local fwd = cf.LookVector
    if (w.turret or w.door) and typeof(e.aim) == "Vector3" then
      local o = (cf * CF(e.def.gunPos or (e.def.door and V(e.def.door.x, e.def.door.y, e.def.door.z)) or V())).Position
      local want = (e.aim - o)
      if want.Magnitude > 1 then
        want = want.Unit
        local lim = w.door and 100 or 85
        if fwd:Dot(want) > math.cos(math.rad(lim)) or w.door then return want, o end
      end
      return fwd, o
    end
    return fwd, (cf * CF(e.def.gunPos or V(0, 0, -e.def.L * 0.45))).Position
  end
  local function stepGuns(dt)
    for _, e in ipairs(aircraft) do
      if e.alive and e.trig and e.driver and e.gunAmmo > 0 and G.round.phase == "battle" then
        local w = AD.W[e.def.gun or ""]
        if w then
          e.gunT += dt
          local nShots = math.min(e.gunAmmo, math.floor(e.gunT / w.rate))
          if nShots > 0 then
            e.gunT -= nShots * w.rate
            e.gunAmmo -= nShots
            local dir, o = gunDir(e, w)
            local spread = 0.006 + (w.door and 0.01 or 0)
            dir = (dir + V((math.random() - 0.5), (math.random() - 0.5), (math.random() - 0.5)) * spread * 2).Unit
            local ww = { dmg = w.dmg * nShots, splash = w.splash, vs = w.vs, id = w.id, fx = "agun" }
            G.launch({ kind = "shell", pos = o + dir * 2, vel = (e.vel or V()) + dir * w.speed, grav = true, gscale = 0.08, w = ww, src = src(e.driver), ignore = ignoreOf(e),
              life = w.range / w.speed + 0.2, byEnt = e.id })
          end
        end
      else
        e.gunT = 0
      end
    end
  end

  -- 热诱弹：一次一组 4 发；正在追这架飞机的红外弹六成被骗走，雷达弹一成五
  local function flare(P, e)
    local t = now()
    if e.flares <= 0 or t < (e.flareNext or 0) then return end
    e.flares = math.max(0, e.flares - 4)
    e.flareNext = t + 1.2
    e.model:SetAttribute("Flares", e.flares)
    local p = e.root.CFrame.Position
    G.fx({ k = "flares", id = e.id, p = p, v = e.vel or V() })
    for _, s in ipairs(G.shots) do
      if s.tgt == e and s.w and (s.w.kind == "aam") then
        local chance = (s.w.seeker == "ir") and 0.6 or 0.15
        if (s.pos - p).Magnitude < 2200 and math.random() < chance then
          s.tgt = { decoy = true, pos = p - (e.vel or V()) * 0.15, vel = (e.vel or V()) * 0.35 + V(0, -10, 0) }
          s.tgId = nil
          G.fx({ k = "shotFix", id = s.id, p = s.pos, v = s.vel, lost = true })
        end
      end
    end
    G.pushOne(P)
  end

  ---------------------------------------------------------------- 飞行同步

  local function crash(e, why)
    if not e.alive then return end
    G.fx({ k = "boom", p = e.root.CFrame.Position, s = 2.8, c = "wreck" })
    G.damageEnt(e, 1e6, e.lastHitBy or { team = "none", name = why or "crash" })
  end

  local function sync(P, e, d)
    local cf = d.cf
    if typeof(cf) ~= "CFrame" then return end
    local t = now()
    local dt = math.max(0.02, t - (e.lastSync or t))
    local p0, p1 = e.root.CFrame.Position, cf.Position
    local dist = (p1 - p0).Magnitude
    local def = e.def
    local maxD = def.vMax * 1.5 * dt + 25
    local bad = dist > maxD or p1.Y ~= p1.Y or math.abs(p1.X) > Map.PLAY + 1200 or math.abs(p1.Z) > Map.PLAY + 1200 or p1.Y > 4000   -- 客户端在 R + 300 开始掉头、R + 1300 硬拦
    e.lastSync = t
    if bad then
      G.R.Drive:FireClient(P.pl, { op = "fix", cf = e.root.CFrame, v = e.vel })
      return
    end
    local g = surface(p1.X, p1.Z)
    if p1.Y < math.max(g, -2) + def.gearH * 0.25 - 2 then   -- 机身插进地里 / 海里
      G.moveEnt(e, cf)
      crash(e, "ground")
      return
    end
    G.moveEnt(e, cf)
    if typeof(d.v) == "Vector3" and d.v.Magnitude < def.vMax * 1.6 then e.vel = d.v end
    if e.onGround and d.gd ~= true then e.upAt = now() end   -- 刚离地（AI 舰艇的自动防空导弹 12 秒内不打：Navy.lua）
    e.onGround = d.gd == true
    if typeof(d.aim) == "Vector3" then e.aim = d.aim end
    local m = e.model
    local function q(name, v, k)
      if type(v) ~= "number" or v ~= v then return end
      v = math.floor(v * k + 0.5) / k
      if m:GetAttribute(name) ~= v then m:SetAttribute(name, v) end
    end
    q("Thr", d.thr, 1)          -- 油门 0～100（加力 100～130）
    q("Gear", d.gear, 10)       -- 起落架 0 收起～1 放下
    q("Flap", d.flap, 10)
    q("Pit", d.cp, 20)          -- 操纵：俯仰、滚转、偏航 −1～1
    q("Rol", d.cr, 20)
    q("Yaw", d.cy, 20)
    q("Bay", d.bay, 10)         -- 弹舱门 0～1
    q("BayS", d.bays, 10)       -- 侧弹舱门
    q("Rpm", d.rpm, 1)          -- 旋翼转速 %
    q("Col", d.col, 20)         -- 总距
    q("Can", d.can, 10)         -- 座舱盖
    q("Hook", d.hook, 10)
    q("Brk", d.brk, 10)         -- 减速板
    q("Ty", d.ty, 2)            -- 机头炮塔：方位、俯仰（度）
    q("Gp", d.gp, 2)
    q("Fold", d.fold, 10)
  end

  local function landedHome(e)
    -- 停在自己的机场 / 甲板 / 停机坪附近：能补弹修理
    local p = e.root.CFrame.Position
    local function near(x, z, r) return (V(p.X, 0, p.Z) - V(x, 0, z)).Magnitude < r end
    if e.team == "atk" then
      local dk = deckOf("carrier")
      if dk and near(dk.cf.Position.X, dk.cf.Position.Z, dk.L * 0.5) then return true end
      dk = deckOf("lhd")
      if dk and near(dk.cf.Position.X, dk.cf.Position.Z, dk.L * 0.5) then return true end
      if near(Map.AFIELD2.x, Map.AFIELD2.z, Map.AFIELD2.len * 0.6) then return true end
      if pointOk("atk", "D") and near(Map.AIRFIELD.x, Map.AIRFIELD.z, Map.AIRFIELD.len * 0.6) then return true end
    else
      if pointOk("def", "D") and near(Map.AIRFIELD.x, Map.AIRFIELD.z, Map.AIRFIELD.len * 0.6) then return true end
      if near(Map.CAMP.x, Map.CAMP.z, 220) then return true end
    end
    return false
  end

  function G.airInput(P, d)
    local e = P.vehicle
    if not e or not e.air or not e.alive or type(d) ~= "table" then return false end
    if e.driver ~= P then
      if d.op == "exit" then unseat(P, e, true) end
      return true
    end
    if d.op == "state" then sync(P, e, d)
    elseif d.op == "trig" then
      e.trig = d.on == true
      e.model:SetAttribute("Fire", e.trig)
      if typeof(d.aim) == "Vector3" then e.aim = d.aim end
    elseif d.op == "fire" then fireStore(P, e, d.w, d.tgt, d.aim)
    elseif d.op == "flare" then flare(P, e)
    elseif d.op == "jettison" then dropTanks(e, false)
    elseif d.op == "crash" then
      local p = e.root.CFrame.Position
      if p.Y - math.max(surface(p.X, p.Z), 0) < e.def.H + 40 or d.hit then crash(e, "ground") end   -- 客户端说撞了：离地面 / 障碍物不远才认
    elseif d.op == "exit" then
      unseat(P, e, true)
    end
    return true
  end
  local driveInput0 = G.driveInput
  function G.driveInput(P, d)
    if P.vehicle and P.vehicle.air then
      G.airInput(P, d)
      return
    end
    if driveInput0 then driveInput0(P, d) end
  end

  -- 给客户端的：自己开的 / 坐的飞机
  local vehState0 = G.vehState
  function G.vehState(P)
    local e = P.vehicle
    if e and e.air then
      if not e.alive then return nil end
      return { id = e.id, m = e.def.id, air = true, pilot = e.driver == P, load = e.load, stores = e.stores, gun = e.gunAmmo, flares = e.flares, home = e.home,
        ground = e.onGround == true, uav = (P.remote == e) or nil, fuel = e.fuel, fuelX = e.fuelX }
    end
    if vehState0 then return vehState0(P) end
    return nil
  end

  ---------------------------------------------------------------- 每帧：机组跟着飞机走；没人开的飞机掉下来；落地补弹

  local gunAcc = 0
  G.onFrame(function(dt)
    gunAcc += dt
    if gunAcc >= 0.1 then
      stepGuns(gunAcc)
      gunAcc = 0
    end
    local t = now()
    for _, e in ipairs(table.clone(aircraft)) do
      local D = e.driver
      if D and (not D.alive or not D.char or not D.char.Parent or G.P[D.pl] ~= D) then
        e.driver = nil
        e.emptyAt = t
        e.trig = false
        e.model:SetAttribute("Driver", 0)
        if D.remote == e then D.remote = nil end
        if e.def.drone then startLoiter(e) end
        D = nil
      end
      for i = #e.pass, 1, -1 do
        local Q = e.pass[i]
        if not Q.alive or not Q.char or not Q.char.Parent or G.P[Q.pl] ~= Q then table.remove(e.pass, i) end
      end
      if D and D.char and D.remote ~= e then D.char:PivotTo(e.root.CFrame) end
      for i, Q in ipairs(e.pass) do if Q.char then Q.char:PivotTo(e.root.CFrame * CF(((i % 2) * 2 - 1) * 2, 0, -2 + i * 2.5)) end end
      if e.alive then burnFuel(e, dt) end
      if e.alive and not D then
        local p = e.root.CFrame.Position
        local g = surface(p.X, p.Z)
        local agl = p.Y - math.max(g, 0) - e.def.gearH
        if e.loit and (t >= e.loit.T or (e.fuel or 1) <= 0) then   -- 盘旋到时候了、或者油烧干了：掉下来
          e.loit = nil
          e.model:SetAttribute("Loiter", false)
        end
        if e.loit and not e.onGround then   -- 断了链路的无人机：自动盘旋，等操作员重连
          loiterStep(e, dt)
        elseif agl > 3 and not e.onGround then   -- 没人开、在天上：往下掉，机头慢慢栽下去
          e.vel = (e.vel or V()) + V(0, -GRAV * 0.8, 0) * dt
          e.vel = e.vel * (1 - 0.15 * dt)
          local np = p + e.vel * dt
          local look = e.vel.Magnitude > 5 and e.vel.Unit or e.root.CFrame.LookVector
          if math.abs(look.Y) > 0.97 then   -- 几乎竖直往下掉（悬停时跳伞、原地放出来的）：留一点机头原来的朝向，不然 lookAt 退化成 NaN，位置跟着变 NaN
            local h = V(e.root.CFrame.LookVector.X, 0, e.root.CFrame.LookVector.Z)
            if h.Magnitude < 0.05 then h = V(0, 0, -1) end
            look = (look + h.Unit * 0.3).Unit
          end
          G.moveEnt(e, CFrame.lookAt(np, np + look) * CFrame.Angles(0, 0, math.sin(t * 1.3) * 0.4))
          if np.Y < math.max(surface(np.X, np.Z), -1) + 2 then crash(e, "ground") end
        elseif not e.onGround then   -- 掉到地面 / 海面上：海里、或者还很快，就是摔了（原来停在离地 3 格的地方漂着不炸）；慢慢落在陆地 / 甲板上才算停住
          if (g <= 0.5 and not AD.onDeck(Map, p.X, p.Z)) or (e.vel and e.vel.Magnitude > 25) then
            crash(e, "ground")
          else
            e.onGround, e.vel = true, V()
          end
        elseif e.emptyAt and t - e.emptyAt > 90 then   -- 停着没人开 90 秒：收走（不算冷却）
          for i, x in ipairs(aircraft) do if x == e then table.remove(aircraft, i) break end end
          G.removeEnt(e)
        end
      end
      -- 落在自己的地方停稳：5 秒后补满弹药、热诱弹，慢慢修
      if e.alive and e.onGround and e.vel and e.vel.Magnitude < 4 and landedHome(e) then
        e.restT = (e.restT or 0) + dt
        if e.restT > 5 then
          if not e.rearmed then
            e.rearmed = true
            e.fuel = math.max(e.fuel or 0, e.fuelSel or 1)   -- 加油：加到出发时选的油量（副油箱在 fillStores 里挂回去加满）
            fillStores(e)
            if e.driver then
              G.msg(e.driver.pl, "good", "ui.rearmed")
              G.pushOne(e.driver)
            end
          end
          if e.hp < e.maxHp then
            e.hp = math.min(e.maxHp, e.hp + e.maxHp * 0.08 * dt)
            e.model:SetAttribute("Hp", math.floor(e.hp))
          end
        end
      else
        e.restT, e.rearmed = 0, false
      end
    end
  end)

  G.on("died", function(P)
    local e = P.vehicle
    if e and e.air then unseat(P, e, false) end
  end)
  G.on("left", function(P)
    local e = P.vehicle
    if e and e.air then unseat(P, e, false) end
  end)
  G.on("roundStart", function()
    for _, e in ipairs(aircraft) do G.removeEnt(e) end
    table.clear(aircraft)
    pending = { atk = {}, def = {} }
  end)
end

return Air
