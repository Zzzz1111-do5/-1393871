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
  G.AirDefs = AD   -- 测试用（ia_carrier：甲板判定）
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
  local REST_WAIT = 3   -- 落地补给：停稳几秒地勤上来
  local SUP_T = ((Config.Wt or {}).airSupT) or 15   -- 加油、挂弹要多久（秒）
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
        for _, id in ipairs(Config.TeamVehicles(team, cat)) do if AD.get(id) then table.insert(out, id) end end   -- 两边的型号都能开
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
        if G.streamFocus then G.streamFocus(P.pl, e.root, true) end   -- 人站在原地遥控：无人机那边也算加载中心（开了 streaming 时画面里有房子、地形细节）
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
      if G.streamFocus then G.streamFocus(P.pl, e.root, false) end
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
    e.restT, e.rearmed = 6, true   -- 新飞机本来就是满的：停在停机位上平显直接写「可以起飞」，不再走一遍补给倒计时
    e.vel = vel or V()
    e.onGround = onGround
    e.pass = {}
    e.lastSync = now()
    e.syncT, e.syncSlack = now(), 160   -- 位置报告的校验（sync）：从这一刻起算
    e.gunT = 0
    e.trig = false
    e.aim, e.stick = nil, nil
    e.bay = 0
    e.model:SetAttribute("Gear", onGround and 1 or 0)
    e.model:SetAttribute("Thr", onGround and 0 or 80)
    e.model:SetAttribute("Rpm", onGround and 0 or 100)
    if G.wtaSetup then G.try("战雷飞机", G.wtaSetup, e) end   -- 战雷式受伤：机翼、尾翼、发动机、油箱、飞行员各一份血（WtAir.lua）
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
        local nk = self.treeKey and ("tree." .. self.treeKey) or ("veh." .. self.def.id)   -- 科技树出的飞机写科技树里的名字
        if src and src.P and G.P[src.P.pl] == src.P then G.msg(src.P.pl, "kill", "ui.vehKilled", { k = nk }) end
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
  -- 空中出生（战雷街机，Tech.lua）：离地、收起落架、顺机头带 speed 的初速（客户端接管时照这个速度飞，不会一出来就失速）
  function G.spawnAircraftAir(team, id, cf, load, P, fuel, speed)
    local d = AD.get(id)
    if not d then return nil end
    local e = newAircraft(team, id, cf, nil, (type(load) == "table") and load or AD.presetLoad(d), cf.LookVector * (speed or 0), false, fuel)
    e.home = "pad"
    e.emptyAt = now()
    e.resP, e.resUntil = P, now() + 30
    return e
  end
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
  -- 主动雷达弹（霹雳-15、AIM-120……；战雷式，用户 11-24 夜：「雷达扫描图……为雷达锁定式导弹提供引导，所以也有 39 机动的这种说法」）：
  --   离目标远时靠发射机的雷达跟踪（数据链）——发射机得一直跟着它（客户端 STT 每半秒报 lockOn → e.radarTgt / e.radarT；边扫边跟每扫一帧报一次，
  --   带 e.radarTws = 一帧几秒，数据链多等这么久），断了就往最后估的拦截点飞（惯导）；
  --   近到 w.act 自己开导引头：只看弹头前方 40°；目标相对地面的速度在视线上的分量小于 w.notch（侧着飞、把导弹放在 3 / 9 点：置零）超过半秒就丢；
  --   开了导引头以后也会被箔条骗（flare 里）。开机以后目标重新进视场、不置零了还能再咬上
  local function arhStep(s, dt)
    local w, ref = s.w, s.ref
    if not ref then return end
    if not ref.alive or not ref.root then
      s.ref = nil
      return
    end
    local rp = ref.root.CFrame.Position
    local dist = (rp - s.pos).Magnitude
    if not s.active and dist > w.act then
      local sh = s.byEnt and G.entById[s.byEnt]
      local dl = sh ~= nil and sh.alive and sh.radarTgt == ref.id and now() - (sh.radarT or -9) < 1.3 + (sh.radarTws or 0)
      s.dl = dl
      if dl then
        if s.tgt ~= ref and not (s.tgt and s.tgt.decoy) then s.tgt, s.tgId, s.aimPt = ref, ref.id, nil end
      elseif s.tgt == ref then   -- 数据链断了：往最后估的拦截点飞
        local tgo = dist / math.max(s.vel.Magnitude, 1)
        s.tgt, s.tgId = nil, nil
        s.aimPt = rp + tgtVel(ref) * math.min(tgo, 6)
        G.fx({ k = "shotFix", id = s.id, p = s.pos, v = s.vel, lost = true })
      end
      return
    end
    if not s.active then
      G.fx({ k = "shotAct", id = s.id })   -- 导引头开机：告诉客户端（雷达屏上这发弹的数据链虚线变实线，WtFlight / Radar.lua）
      -- 边扫边跟打出去的（发射时对方的告警器不知道）：导引头开机这时候才报「导弹来袭」
      if s.rwrLate and ref.driver and ref.driver.pl then G.R.Drive:FireClient(ref.driver.pl, { op = "rwr", id = s.id, w = s.rwrLate }) end
      s.rwrLate = nil
    end
    s.active = true
    if s.tgt and s.tgt.decoy then return end   -- 被箔条骗走了
    local los = (rp - s.pos) / math.max(dist, 1)
    local fov = s.vel.Magnitude > 1 and s.vel.Unit:Dot(los) > math.cos(math.rad(40))
    local notched = math.abs(tgtVel(ref):Dot(los)) < (w.notch or 50) and dist > 250
    s.notched = notched
    if fov and not notched then
      s.notchT = 0
      if s.tgt ~= ref then s.tgt, s.tgId, s.aimPt = ref, ref.id, nil end   -- 开机咬上 / 重新咬上
    else
      s.notchT = (s.notchT or 0) + dt
      if s.tgt == ref and s.notchT > 0.5 then
        s.tgt, s.tgId = nil, nil
        s.aimPt = rp + tgtVel(ref) * 0.5
        G.fx({ k = "shotFix", id = s.id, p = s.pos, v = s.vel, lost = true })
      end
    end
  end
  G.airArhStep = arhStep   -- 测试用

  local function guideMissile(s, dt)
    -- 抛射（用户 11-25「部分直升机我记得发射导弹是抛射」「或许不止直升机」）：弹舱、机身半埋挂点的中距弹被弹射器推出去，
    --   直升机的筒射防空弹（毒刺、天燕-90、针-V、西北风）先被抛射药推出发射筒——往下掉 ejT 秒、离开飞机，发动机才点火、开始制导
    if s.ejT and (s.ejAge or 0) < s.ejT then
      s.ejAge = (s.ejAge or 0) + dt
      s.vel += V(0, -GRAV, 0) * dt
      s.vel = s.vel * (1 - 0.04 * dt)
      if s.ejAge >= s.ejT then G.fx({ k = "shotIgn", id = s.id }) end   -- 客户端：这时候才喷火、拖烟
      s.fixT = (s.fixT or 0) + dt
      if s.fixT > 0.15 then
        s.fixT = 0
        G.fx({ k = "shotFix", id = s.id, p = s.pos, v = s.vel })
      end
      return false
    end
    s.age += dt
    local w = s.w
    if w.seeker == "radar" and w.act and s.ref then arhStep(s, dt) end
    local spd = s.vel.Magnitude
    -- 发动机开着（助推 / 主发动机、霹雳-15 的第二次脉冲、巡航弹一直开）往最快加；关了按阻力掉速（∝ 速度²，各型的 bleed 不一样：
    --   大的弹掉得慢；用户 11-24 夜：「不同导弹尾烟 动能 速度都是不一样的」）
    if AD.motorOn(w, s.age) then spd = math.min(w.speed, spd + w.speed * 1.4 * dt)
    else spd = spd - (w.bleed or 0.12) * w.speed * (spd / w.speed) ^ 2 * dt end
    spd = math.max(spd, w.speed * 0.22)
    local dir = s.vel.Unit
    local t = s.tgt
    if t and t.decoy then t.pos += t.vel * dt t.vel += V(0, -GRAV * 0.4, 0) * dt end
    local tp = tgtPos(t)
    -- 激光制导的弹冲着装了激光告警的坦克去：报警、自动烟幕；烟幕挡住照射点（或 JD-3 把照射干扰掉）就丢了目标（Kit.lua）
    if tp and t and not t.decoy and w.guide == "laser" and G.kitLaser and G.kitLaser(s, t, dt) then
      s.tgt, s.aimPt, t, tp = nil, nil, nil, nil
    end
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
        -- 能拉多少过载按速度² 算（满速时 w.g 个 g）：后段掉了速的弹转不动——战雷里「拖到导弹没能量再急转」躲得掉；
        --   转弯也掉能量（诱导阻力）
        local aMax = (w.g or 30) * GRAV * (spd / math.max(w.speed, 1)) ^ 2
        local wMax = math.min(math.rad(w.turn), aMax / math.max(spd, 1))
        local nd = turnToward(dir, want, wMax * dt * k)
        local used = math.acos(math.clamp(nd:Dot(dir), -1, 1)) / math.max(dt, 1e-3)
        spd = math.max(w.speed * 0.22, spd - 0.04 * (used * spd) ^ 2 / ((w.g or 30) * GRAV) * dt)
        dir = nd
      end
      local fuse = 8 + ((t and not t.decoy and t.root) and math.min(14, t.root.Size.Magnitude * 0.18) or 0)
      -- 这一步里离目标最近是多远（导弹、目标都在动）：C 11-25 ⑩ 导弹按真实速度飞（一步四五十格），只看步头会从近炸圈里穿过去
      local dvR = dir * spd - tgtVel(t)
      local rel = s.pos - tp
      local tt = math.clamp(-rel:Dot(dvR) / math.max(dvR:Dot(dvR), 1e-6), 0, dt)
      local dmin = (rel + dvR * tt).Magnitude
      if dist < fuse or dmin < fuse then
        local bp = (dist < fuse) and s.pos or (s.pos + dir * spd * tt)
        if t and t.decoy then G.fx({ k = "boom", p = bp, s = 0.6, c = "msl" }) return true end
        G.explode(bp, w, s.src)
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
  G.airGuideMissile = guideMissile   -- 地面车的地空导弹也按这套飞（Armor.lua：铠甲-S1 的 57E6）
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
  G.airBombStep = guideBomb   -- 测试用（客户端 Marks.lua 的炸弹落点按同一套算）
  local function guideRocket(s, dt)
    s.age += dt
    s.vel += V(0, -GRAV * 0.25, 0) * dt
    return false
  end

  -- 挂点的世界位置
  --   歼-20 侧弹舱（AirDefs 的 sideArm）：霹雳-10 在挂架转出舱外的位置发射（s.pos 是收在舱里的位置）
  local function stationWorld(e, s)
    local arm = e.def.sideArm
    if arm and s.bay and s.bay ~= "main" then
      local sd = (s.pos.X >= 0) and 1 or -1
      local P = Vector3.new(sd * arm.p.X, arm.p.Y, s.pos.Z)
      return e.root.CFrame * CF((CF(P) * CFrame.Angles(0, 0, -sd * arm.A) * CF(s.pos - P)).Position)
    end
    return e.root.CFrame * CF(s.pos)
  end
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
    local use = r * dt + ((G.wtaLeak and G.wtaLeak(e)) or 0) * dt   -- 油箱被打漏了（WtAir.lua）：多漏掉的
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

  -- n、rip：战雷的投弹数量（客户端 Shift + B）——n 枚炸弹，双投两枚同时出，齐投（rip）一枚接一枚隔 BOMB_GAP 秒
  local BOMB_GAP = 0.08
  local function fireStore(P, e, wid, tid, aim, n, rip)
    local w = AD.W[type(wid) == "string" and wid or ""]
    if not w or w.kind == "gun" or w.kind == "tank" then return end   -- 副油箱不是弹（抛油箱走 jettison）
    -- 没开战不能打；试驾（训练场，Tech.lua e.testDrive）除外——真游戏开着匹配，机库里试驾时这一局还在「匹配中」，原来靶机、靶车一发都打不了
    if G.round.phase ~= "battle" and not e.testDrive then return end
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
    if w.nuke then   -- 「惊雷-1」高超音速战术核导弹（Nuke.lua）：先看这一队能不能发（冷却、开战多久），再按空射弹道导弹的弹道飞
      local ok, why, n = true, nil, nil
      if G.nukeCheck then ok, why, n = G.nukeCheck(e.team) end
      if not ok or not G.nukeArm then
        if P and P.pl and why then G.msg(P.pl, "bad", why, n) end
        return
      end
      local launch = scf.Position - scf.UpVector * 2.5
      local H = G.nukeArm(e.team, launch, aimPt or (launch + fwd * 9000))
      S = S or { team = e.team, name = "H-6K" }
      S.wid = "hn1"
      G.launch({ kind = "missile", pos = launch, vel = base - scf.UpVector * 10, w = w, src = S, ignore = ignoreOf(e), life = w.life or 90,
        step = G.nukeGuide, age = 0, hyper = H, byEnt = e.id })
      e.nextStore = t + 1
    elseif w.kind == "aam" or w.kind == "agm" then
      local launch = scf.Position - scf.UpVector * 1.2
      -- 抛射（AirDefs.EJ）：弹本身标了 eject（筒射的、投放的、只用弹射挂架的），或者挂在主弹舱、弹射挂点（挂点标了 ej）；
      --   其余的（响尾蛇、霹雳-10 的导轨、侧弹舱伸出去的导轨、地狱火）照旧：在导轨上点火冲出去
      local ej = w.eject or ((s.ej or s.bay == "main") and "drop") or nil
      local E = ej and (type(ej) == "table" and ej or AD.EJ[ej]) or nil
      -- 对边扫边跟的航迹打主动雷达弹（没有 STT，客户端报的 lockOn 带 tws）：对方的告警器这时不报，等导引头开机（arhStep）
      local quiet = tgt ~= nil and w.seeker == "radar" and w.act ~= nil and e.radarTws ~= nil and e.radarTgt == tgt.id
      local sh = G.launch({ kind = "missile", pos = launch, vel = E and (base + fwd * E.f - scf.UpVector * E.d) or (base + fwd * 60 - scf.UpVector * 6),
        w = w, src = S, ignore = ignoreOf(e), life = (w.life or 8) + (E and E.t or 0),
        step = guideMissile, age = 0, ejT = E and E.t or nil, tgt = tgt, tgId = tgt and tgt.id or nil, aimPt = (not tgt and w.kind == "agm") and aimPt or nil, byEnt = e.id,
        ref = (w.seeker == "radar" and w.act) and tgt or nil })   -- 主动雷达弹：记住真正的目标（数据链 / 开导引头按它）
      e.nextStore = t + 0.35
      if quiet then
        sh.rwrLate = wid
      elseif tgt and tgt.driver then
        G.R.Drive:FireClient(tgt.driver.pl, { op = "rwr", id = sh.id, w = wid })
      end
    elseif w.kind == "bomb" then
      local function drop(j)
        local c2 = stationWorld(e, e.def.st[j])
        local tg = (tgt and tgt.alive) and tgt or nil
        G.launch({ kind = "bomb", pos = c2.Position - c2.UpVector * 1.5, vel = (e.vel or V()) - c2.UpVector * 4, w = w, src = S, ignore = ignoreOf(e), life = 30,
          step = guideBomb, age = 0, tgt = tg, tgId = tg and tg.id or nil, aimPt = aimPt, byEnt = e.id })
        spend(e, j)
        G.fx({ k = "storeOff", id = e.id, st = j, w = wid })
      end
      drop(i)
      local cnt = math.clamp(math.floor(tonumber(n) or 1), 1, 60)
      local gap = (rip == true) and BOMB_GAP or 0
      for k = 2, cnt do
        local function nextOne()
          if not e.alive or (G.round.phase ~= "battle" and not e.testDrive) then return end
          local j = pickStation(e, wid)   -- 剩得多的挂点先投：左右轮流
          if j then drop(j) end
        end
        if gap > 0 then task.delay(gap * (k - 1), nextOne) else nextOne() end
      end
      e.nextStore = t + gap * (cnt - 1) + ((e.def.bomber) and 0.12 or 0.25)
      return   -- 上面每枚都扣过数了
    elseif w.kind == "rkt" then
      local dir = (fwd + V((math.random() - 0.5) * 0.02, (math.random() - 0.5) * 0.02, (math.random() - 0.5) * 0.02)).Unit
      G.launch({ kind = "rocket", pos = scf.Position + fwd * 3, vel = base + dir * w.speed, w = w, src = S, ignore = ignoreOf(e), life = w.range / w.speed + 1,
        step = guideRocket, age = 0, byEnt = e.id })
      e.nextStore = t + w.rate
    end
    spend(e, i)
    G.fx({ k = "storeOff", id = e.id, st = i, w = wid })
  end

  -- 雷达锁定告警（战雷的 RWR：被敌机雷达锁着，告警一阵阵嘀嘀响）：客户端雷达 STT 跟踪着敌机半秒报一次（Radar.lua，跟选的什么弹无关）；
  --   服务器看一眼（敌方、飞机、12000 格以内）转告被锁那架的飞行员（Fly.lua 的 rwrLock）；红外弹是被动的，不报。
  --   tws（数字，一帧几秒）：边扫边跟指定的航迹更新了——只记下来给数据链用（等一帧），**不发 rwrLock**（对方的告警器分不出边扫边跟）
  local function lockOn(e, tid, full, tws)
    local tg = (type(tid) == "string") and G.entById[tid] or nil
    if not tg or not tg.alive or not tg.air or tg.team == e.team or not tg.root or not e.root then return end
    local tn = now()
    local twsS = (type(tws) == "number" and tws == tws) and math.clamp(tws, 0.2, 12) or nil
    if (tg.root.CFrame.Position - e.root.CFrame.Position).Magnitude < 20000 then
      e.radarTgt, e.radarT, e.radarTws = tg.id, tn, twsS   -- 雷达跟踪着它：飞出去的主动雷达弹按这个走数据链（arhStep）
    end
    if twsS then return end
    if tn < (e.lockPingT or 0) then return end
    e.lockPingT = tn + 0.35
    if (tg.root.CFrame.Position - e.root.CFrame.Position).Magnitude > 12000 then return end
    if tg.driver and tg.driver.pl then G.R.Drive:FireClient(tg.driver.pl, { op = "rwrLock", by = e.id, full = full == true }) end
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
    local o = (cf * CF(e.def.gunPos or V(0, 0, -e.def.L * 0.45))).Position
    if e.driver and e.stick and typeof(e.aim) == "Vector3" then   -- 固定机炮黏住目标（用户 11-21：像 MWT 那样）：客户端给的瞄准点在机头 12° 以内就朝它打
      local want = e.aim - o
      if want.Magnitude > 1 and fwd:Dot(want.Unit) > math.cos(math.rad(12)) then return want.Unit, o end
    end
    return fwd, o
  end
  -- 近似正态分布（三个均匀分布相加），标准差 1
  local function gauss() return (math.random() + math.random() + math.random() - 1.5) * 2 end
  -- 航炮：每发单独打（原来一步里几发合成一发、方向一样，看着像一道激光；用户：飞机机炮要有散布、后坐力和打击感）——
  --   散布按真炮的量级（标准差约 4.5 毫弧度：200 米外一发偏一米左右），连着打越久越散（炮管、机体振动，打满 2 秒到将近两倍），门炮再大一些；
  --   同一步里的几发沿弹道错开（射速间隔 × 弹速），不叠在一个点上
  local function stepGuns(dt)
    for _, e in ipairs(aircraft) do
      if e.alive and e.trig and e.driver and e.gunAmmo > 0 and (G.round.phase == "battle" or e.testDrive) then   -- 试驾：匹配中也能打靶
        local w = AD.W[e.def.gun or ""]
        if w then
          e.gunT += dt
          e.gunHeat = math.min(3, (e.gunHeat or 0) + dt)
          local nShots = math.min(e.gunAmmo, math.floor(e.gunT / w.rate))
          if nShots > 0 then
            e.gunT -= nShots * w.rate
            e.gunAmmo -= nShots
            local dir0, o = gunDir(e, w)
            local sp = ((w.disp or 0.0045) + (w.door and 0.01 or 0)) * (1 + math.min(1, e.gunHeat / 2) * 0.9)
            local right = dir0:Cross(V(0, 1, 0))
            if right.Magnitude < 1e-3 then right = V(1, 0, 0) end
            right = right.Unit
            local up = right:Cross(dir0).Unit
            for k = 1, nShots do
              local dir = (dir0 + right * (gauss() * sp) + up * (gauss() * sp)).Unit
              local ww = { dmg = w.dmg, splash = w.splash, vs = w.vs, id = w.id, fx = "agun" }
              G.launch({ kind = "shell", pos = o + dir * (2 + (k - 1) * w.rate * w.speed), vel = (e.vel or V()) + dir * w.speed, grav = true, gscale = 0.08, w = ww,
                src = src(e.driver), ignore = ignoreOf(e), life = w.range / w.speed + 0.2, byEnt = e.id })
            end
          end
        end
      else
        e.gunT = 0
        e.gunHeat = math.max(0, (e.gunHeat or 0) - dt * 1.5)
      end
    end
  end

  -- 热诱弹：一次一组 4 发；正在追这架飞机的红外弹六成被骗走，雷达弹一成五
  -- 热诱弹（用户：改成按住连续放）：客户端按住 X 每 0.3 秒发一次，一次放 2 发（原来按一下放 4 发、冷却 1.2 秒）；
  --   每放一组，追着这架飞机的空空弹有一定机会被骗走（连着放几组，红外弹多半被骗走）
  local function flare(P, e)
    local t = now()
    if e.flares <= 0 or t < (e.flareNext or 0) then return end
    local n = math.min(2, e.flares)
    e.flares = math.max(0, e.flares - n)
    e.flareNext = t + 0.25
    e.model:SetAttribute("Flares", e.flares)
    local p = e.root.CFrame.Position
    G.fx({ k = "flares", id = e.id, p = p, v = e.vel or V(), n = n })
    for _, s in ipairs(G.shots) do
      if s.tgt == e and s.w and (s.w.kind == "aam" or (s.w.kind == "sam" and s.w.seeker == "ir")) then   -- 红外地空弹（箭-1 的 9M31）也看热诱弹
        -- 红外弹看热诱弹（三成被骗）；雷达弹看箔条（每组诱饵弹里都有：战雷那样）——只有开了导引头的才会被骗（数据链阶段不看），
        --   同时在置零（侧着飞）的话更容易（战雷里「置零 + 箔条」是躲雷达弹的标准动作）
        local chance
        if s.w.seeker == "ir" then
          chance = 0.33
        elseif s.w.act then
          chance = s.active and ((s.notched or (s.notchT or 0) > 0) and 0.5 or 0.2) or 0
        else
          chance = 0.07
        end
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

  -- 飞得快一卡一卡（用户 11-18）：原来按「两次收到报告的间隔」算允许飞多远（最少按 0.02 秒）——报告挤在一起到（客户端帧率低、网络抖、
  --   服务器一帧处理两包），高速时一包挪的距离就超了，服务器把飞机拉回上一个位置，客户端一顿一顿地往回跳。
  --   现在按「离上次认下的位置过了多久」算（挤在一起到的两包，第二包允许的距离也是按真实经过的时间），再加一个会慢慢回满的余量；
  --   超出一点的不拉回客户端、服务器这边先挪到允许的地方，差得太远（瞬移、出界）才拉回
  local function sync(P, e, d)
    local cf = d.cf
    if typeof(cf) ~= "CFrame" then return end
    local t = now()
    local dtA = math.max(0, t - (e.syncT or t))
    e.syncT = t
    local p0, p1 = e.root.CFrame.Position, cf.Position
    local dist = (p1 - p0).Magnitude
    local def = e.def
    e.syncSlack = math.min(160, (e.syncSlack or 160) + dtA * 120)
    local allow = def.vMax * 1.6 * dtA
    -- 作战区按所在的区块（Zones.lua：训练场在十万格外，按训练场中心、训练场的作战区算）；客户端在作战区边上开始掉头、再往外 1000 硬拦
    local rx, rz, zn = p1.X, p1.Z, "battle"
    if Map.Zones then rx, rz, zn = Map.Zones.rel(p1.X, p1.Z) end
    local lim = (Map.Zones and Map.Zones.play(zn, Map) or Map.PLAY) + 1200
    local bad = p1.Y ~= p1.Y or math.abs(rx) > lim or math.abs(rz) > lim or p1.Y > (Map.CEIL or 2600) + 1400   -- 升限按地图（雪山 7200）
    if not bad and dist > allow then
      local over = dist - allow
      if over <= e.syncSlack then
        e.syncSlack -= over
      elseif over > e.syncSlack + 600 then
        bad = true   -- 差得太远：瞬移、改了速度
      else
        cf = CFrame.new(p0 + (p1 - p0).Unit * (allow + e.syncSlack)) * cf.Rotation   -- 服务器先挪到允许的地方，不拉回客户端，下一包接着追
        p1 = cf.Position
        e.syncSlack = 0
      end
    end
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
    e.stick = d.stk == true   -- 机炮黏住了目标（客户端 Fly.lua 的 gunStick）
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
    local HB = Map.BASES and Map.BASES[e.team]
    if HB then   -- 沙海：自己主基地（跑道、直升机坪、营区）
      local A = HB.airfield
      if near(A.x, A.z, A.len * 0.6) then return true end
      if near(HB.heli.x, HB.heli.z, 260) or near(HB.camp.x, HB.camp.z, 600) then return true end
      return false
    end
    if e.team == "atk" then
      local dk = deckOf("carrier")
      if dk and near(dk.cf.Position.X, dk.cf.Position.Z, dk.L * 0.5) then return true end
      dk = deckOf("lhd")
      if dk and near(dk.cf.Position.X, dk.cf.Position.Z, dk.L * 0.5) then return true end
      if near(Map.AFIELD2.x, Map.AFIELD2.z, Map.AFIELD2.len * 0.6) then return true end
      if Map.REDBASE and near(Map.REDBASE.x, Map.REDBASE.z, 500) then return true end   -- 沙漠图：前进基地的直升机坪
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
      e.stick = d.stk == true
    elseif d.op == "fire" then fireStore(P, e, d.w, d.tgt, d.aim, d.n, d.rip)
    elseif d.op == "lockOn" then lockOn(e, d.tgt, d.full, d.tws)
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
        ground = e.onGround == true, uav = (P.remote == e) or nil, fuel = e.fuel, fuelX = e.fuelX,
        v = (not e.onGround and e.vel and e.vel.Magnitude > 1) and e.vel or nil }   -- 空中出生的初速（Fly.lua begin 接着这个速度飞）
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
      -- 落地补给（用户 11-25「回跑道降落补给也做出来」，照战雷）：落在自己的机场 / 甲板上停稳 3 秒，地勤开始干活——
      --   油按时间加（SUP_T 秒加到出发时选的油量），弹药、热诱弹、副油箱到时候一起挂上；同时修：机身血每秒一成，
      --   战雷式部件（WtAir.lua wtaRepair：发动机、机翼、尾翼、油箱、操纵面、飞行员，灭火、堵漏、修起落架）每秒修 8 点多；
      --   Rest 属性给平显看（Fly.lua）：1～3 停稳倒计时、10 在自己的机场 / 甲板上还在滑、−1 补给 / 维修中（RestK 进度 0～1）、−2 全好了、−3 这里补不了
      local rest, restK = 0, nil
      if e.alive and e.onGround then
        local fixed0 = (not G.wtaFixK or G.wtaFixK(e) >= 1) and e.hp >= e.maxHp
        if not landedHome(e) then
          rest = -3
          e.restT = 0
        elseif e.vel and e.vel.Magnitude < 4 then
          e.restT = (e.restT or 0) + dt
          if e.restT > REST_WAIT then
            if not e.rearmed then
              if not e.supK then e.supK, e.fuel0 = 0, e.fuel or 0 end
              e.supK = math.min(1, e.supK + dt / SUP_T)
              e.fuel = e.fuel0 + math.max(0, (e.fuelSel or 1) - e.fuel0) * e.supK
              pushFuel(e)
              if e.supK >= 1 then
                e.rearmed, e.supK = true, nil
                e.fuel = math.max(e.fuel or 0, e.fuelSel or 1)   -- 加油：加到出发时选的油量（副油箱在 fillStores 里挂回去加满）
                fillStores(e)
                if e.driver then
                  G.msg(e.driver.pl, "good", "ui.rearmed")
                  G.pushOne(e.driver)
                end
              end
            end
            local partsOk = true
            if G.wtaRepair and not G.wtaNoRepair then partsOk = G.wtaRepair(e, dt) end   -- G.wtaNoRepair：测部件伤害的测试（停在自己营地边上挨打）
            if e.hp < e.maxHp then
              e.hp = math.min(e.maxHp, e.hp + e.maxHp * 0.1 * dt)
              e.model:SetAttribute("Hp", math.floor(e.hp))
            end
            local done = e.rearmed and partsOk and e.hp >= e.maxHp
            rest = done and -2 or -1
            if not done then
              restK = math.min(e.rearmed and 1 or (e.supK or 0), e.hp / math.max(1, e.maxHp), (G.wtaFixK and G.wtaFixK(e)) or 1)
              restK = math.floor(restK * 100) / 100
            end
          else
            rest = math.max(1, math.ceil(REST_WAIT - e.restT))
          end
        else
          rest = (e.rearmed and fixed0) and 0 or 10   -- 补好了的在跑道上滑（起飞滑跑）：不写字
          e.restT = 0
        end
      else
        e.restT, e.rearmed, e.supK = 0, false, nil   -- 飞起来了：下次落地再补
      end
      if e.alive and e.model and e.model:GetAttribute("RestK") ~= restK then e.model:SetAttribute("RestK", restK) end
      if e.alive and e.model and e.model:GetAttribute("Rest") ~= rest then e.model:SetAttribute("Rest", rest) end
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
