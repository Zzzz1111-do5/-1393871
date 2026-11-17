-- Roblox全面大战场——步兵武器（背包里的工具）：发武器（按兵种）、开火（服务器校验射速、弹匣、备弹、射程、拿着的是不是这把）、
--   枪：射线判定，爆头加成；火箭筒 / 手雷 / 防空导弹：飞行中的弹（Ents）；迫击炮：点地面，几秒后落下；急救包；扳手修车；
--   炸药包（放下、再用一次引爆）；破障器材（探雷、排雷、剪铁丝网，逻辑在 Forts）；望远镜：标记敌人给全队看，呼叫炮火覆盖
local Weapons = {}

function Weapons.init(G)
  local Config, Map = G.Config, G.Map
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local W = Config.Weapons
  local now = os.clock
  local RS = game:GetService("ReplicatedStorage")
  local GD = require(RS:WaitForChild("GearDefs"))
  local TURN = require(RS:WaitForChild("ImportTurn")).TURN   -- 导入的每块网格被 Roblox 转了半圈（ImportTurn.lua）：装的时候转回来
  local OM = nil   -- 手持装备真模型的元数据（OpticsMeta：块的中心、握把、枪口……）
  do
    local ok, r = pcall(function() return require(RS:WaitForChild("OpticsMeta", 5)) end)
    if ok and type(r) == "table" then OM = r end
  end

  ---------------------------------------------------------------- 工具的样子（零件拼的；把手 Handle 在握把处，枪口 Muzzle）

  local function p(parent, size, cf, color, mat, shape)
    local x = Instance.new("Part")
    if shape then x.Shape = shape end
    x.Size, x.CFrame, x.Color = size, cf, color
    x.Material = mat or Enum.Material.SmoothPlastic
    x.CanCollide, x.CanQuery, x.CanTouch, x.Massless = false, false, false, true
    x.TopSurface, x.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    x.Parent = parent
    return x
  end
  local function weld(a, b)
    local w = Instance.new("WeldConstraint")
    w.Part0, w.Part1 = a, b
    w.Parent = a
  end
  local GUN, DARK, OLIVE, TAN = RGB(48, 50, 52), RGB(30, 31, 33), RGB(86, 96, 64), RGB(176, 156, 112)
  -- 每把武器：枪身长 L、枪管长、枪托、弹匣……；返回把手和枪口
  local SHAPE = {
    m4 = { L = 2.9, barrel = 1.3, stock = true, mag = 0.95, color = RGB(40, 40, 42), rail = true, acog = true },
    sniper = { L = 4.0, barrel = 2.2, stock = true, scope = true, mag = 0.6, color = RGB(70, 66, 52) },
    rpg = { tube = 4.6, dia = 0.7, color = OLIVE, warhead = true },
    manpads = { tube = 5.0, dia = 0.6, color = RGB(64, 72, 60), sight = true },
    mortar = { tube = 3.4, dia = 0.75, color = OLIVE, plate = true },
  }
  -- 真模型（Studio 里导入了 models/optics/<键>.glb，Imports.lua 收进 Imported.Optics.<键>）：块按「握把坐标」（GearDefs）装到把手上——
  --   握把在把手处，工具的枪口朝 −Z、器材坐标朝 +Z：转 180°
  local FLIP = CFrame.Angles(0, math.pi, 0)
  local function attachReal(tool, h, key, base, prefix)
    local imp = RS:FindFirstChild("Imported")
    local f = imp and imp:FindFirstChild("Optics")
    f = f and f:FindFirstChild(key)
    local M = OM and OM[key]
    if not f or not M then return 0 end
    local n = 0
    for _, src in ipairs(f:GetChildren()) do
      local name = string.match(src.Name, "__(.+)$")
      local info = name and M.parts[name]
      if src:IsA("BasePart") and info then
        local q = src:Clone()
        q.Name = prefix .. name
        q.Anchored, q.CanCollide, q.CanQuery, q.CanTouch, q.Massless = false, false, false, false, true
        q.CFrame = base * CF(info.c[1], info.c[2], info.c[3]) * TURN
        q.Parent = tool
        weld(h, q)
        n += 1
      end
    end
    return n
  end
  -- 整件换成真模型；没导入返回 nil（照旧零件拼），导入了返回枪口 / 筒口（工具坐标）
  local function addGear(tool, h, key)
    local M = OM and OM[key]
    if not M then return nil end
    local base = FLIP * GD.grip(M)
    if attachReal(tool, h, key, base, "Gear_") == 0 then return nil end
    local mt = GD.MOUNT[key]
    if mt and attachReal(tool, h, mt.key, base * GD.mountAt(key, M), "Scope_") == 0 then   -- 枪导入了、镜子没导入：零件拼一根镜筒
      local sc = p(tool, V(1.1, 0.16, 0.16), base * GD.mountAt(key, M) * CF(0, 0.14, 0) * CFrame.Angles(0, math.pi / 2, 0), DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
      sc.Name = "Scope"
      weld(h, sc)
    end
    local mz = GD.muzzle(M)
    return mz and (base * mz) or V(0, 0.3, -1)
  end
  -- 破障器材：探雷器（杆子 + 探头圆盘）
  local function makeTool(id, team)
    local tool = Instance.new("Tool")
    tool.Name = id
    tool.CanBeDropped = false
    tool.RequiresHandle = true
    tool:SetAttribute("Weapon", id)
    local h = p(tool, V(0.4, 0.9, 0.5), CF(), GUN)
    h.Name = "Handle"
    h.Transparency = 1
    local S = SHAPE[id]
    local muzzle = V(0, 0.3, -1)
    -- 按阵营用哪件真模型（GearDefs）：第一人称（FPSView）照这两个属性用同一套
    local key = GD.key(id, team)
    if key then tool:SetAttribute("Gear", key) end
    if key and GD.MOUNT[key] then tool:SetAttribute("GearMount", GD.MOUNT[key].key) end
    local realMz = key and addGear(tool, h, key)
    if realMz then
      muzzle = realMz
    elseif S and S.L then   -- 枪：沿 −Z 朝前
      local th = S.small and 0.35 or 0.45
      local body = p(tool, V(th, 0.5, S.L), CF(0, 0.3, -S.L / 2 + 0.6), S.color)
      weld(h, body)
      local br = p(tool, V(S.thick and 0.32 or 0.18, S.thick and 0.32 or 0.18, S.barrel), CF(0, 0.38, -S.L + 0.6 - S.barrel / 2), DARK, Enum.Material.Metal)
      weld(h, br)
      muzzle = V(0, 0.38, -S.L + 0.6 - S.barrel)
      if S.stock then weld(h, p(tool, V(0.35, 0.55, 1.1), CF(0, 0.2, 1.1), S.color)) end
      if S.mag then weld(h, p(tool, V(0.3, S.mag, 0.45), CF(0, -0.25, -0.8), DARK)) end
      if S.box then weld(h, p(tool, V(0.6, 0.6, 0.7), CF(0.35, -0.1, -0.7), OLIVE)) end
      if S.scope then   -- 瞄准镜：Studio 里导入了真模型（models/optics/atacr.glb，Imports.lua 收进 Imported.Optics.atacr）就装它，不然零件拼一根镜筒
        local imp = RS:FindFirstChild("Imported")
        local opt = imp and imp:FindFirstChild("Optics")
        opt = opt and opt:FindFirstChild("atacr")
        local real = false
        if opt and OM and OM.atacr then
          for _, src in ipairs(opt:GetChildren()) do
            local name = string.match(src.Name, "__(.+)$")
            local info = name and OM.atacr.parts[name]
            if src:IsA("BasePart") and info then   -- 器材坐标 +Z 朝前、原点在镜座底面；工具 −Z 朝前：转 180°，镜座贴在枪身顶面（y 0.55）
              local q = src:Clone()
              q.Name = "Scope_" .. name
              q.Anchored, q.CanCollide, q.CanQuery, q.CanTouch, q.Massless = false, false, false, false, true
              q.CFrame = CF(0, 0.55, -1.1) * CFrame.Angles(0, math.pi, 0) * CF(info.c[1], info.c[2], info.c[3]) * TURN
              q.Parent = tool
              weld(h, q)
              real = true
            end
          end
        end
        if not real then
          local sc = p(tool, V(1.3, 0.28, 0.28), CF(0, 0.75, -0.6) * CFrame.Angles(0, math.pi / 2, 0), DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
          sc.Name = "Scope"
          weld(h, sc)
        end
      end
      if S.rail then weld(h, p(tool, V(0.22, 0.1, S.L * 0.55), CF(0, 0.6, -S.L * 0.3), DARK, Enum.Material.Metal)) end
      if S.acog then   -- 导轨上一具 ACOG（用户：武器瞄准没有镜子）：导入了真模型（models/optics/acog.glb）就装它（按枪放大 1.2 倍），不然零件拼一具
        local imp = RS:FindFirstChild("Imported")
        local opt = imp and imp:FindFirstChild("Optics")
        opt = opt and opt:FindFirstChild("acog")
        local base = CF(0, 0.65, -0.5) * CFrame.Angles(0, math.pi, 0)   -- 镜座底面贴导轨顶面；器材 +Z 朝前、工具 −Z 朝前：转 180°
        local real = false
        if opt and OM and OM.acog then
          for _, src in ipairs(opt:GetChildren()) do
            local name = string.match(src.Name, "__(.+)$")
            local info = name and OM.acog.parts[name]
            if src:IsA("BasePart") and info then
              local q = src:Clone()
              q.Name = "Scope_" .. name
              q.Size = src.Size * 1.2
              q.Anchored, q.CanCollide, q.CanQuery, q.CanTouch, q.Massless = false, false, false, false, true
              q.CFrame = base * CF(info.c[1] * 1.2, info.c[2] * 1.2, info.c[3] * 1.2) * TURN
              q.Parent = tool
              weld(h, q)
              real = true
            end
          end
        end
        if not real then
          local body = p(tool, V(0.17, 0.17, 0.4), base * CF(0, 0.12, -0.02), DARK, Enum.Material.Metal)
          body.Name = "Scope"
          weld(h, body)
          weld(h, p(tool, V(0.1, 0.24, 0.24), base * CF(0, 0.12, 0.2) * CFrame.Angles(0, math.pi / 2, 0), DARK, Enum.Material.Metal, Enum.PartType.Cylinder))   -- 物镜
          weld(h, p(tool, V(0.1, 0.06, 0.2), base * CF(0, 0.035, -0.02), DARK, Enum.Material.Metal))   -- 镜座
          weld(h, p(tool, V(0.035, 0.03, 0.26), base * CF(-0.015, 0.215, 0.07), RGB(200, 40, 30), Enum.Material.Neon))   -- 顶上的红色光纤
        end
      end
    elseif S and S.tube then   -- 发射筒：扛在肩上
      local t = p(tool, V(S.tube, S.dia, S.dia), CF(0, 0.6, -0.4) * CFrame.Angles(0, math.pi / 2, 0), S.color, Enum.Material.Metal, Enum.PartType.Cylinder)
      weld(h, t)
      muzzle = V(0, 0.6, -0.4 - S.tube / 2)
      if S.warhead then weld(h, p(tool, V(0.9, 0.9, 1.2), CF(0, 0.6, muzzle.Z - 0.3), OLIVE, Enum.Material.Metal)) end
      if S.sight then weld(h, p(tool, V(0.3, 0.6, 0.8), CF(-0.5, 1.0, -0.6), DARK)) end
      if S.plate then weld(h, p(tool, V(1.4, 0.15, 1.4), CF(0, -0.1, 1.2), DARK)) end
    elseif id == "grenade" then
      weld(h, p(tool, V(0.7, 0.7, 0.7), CF(0, 0.2, -0.3), OLIVE, Enum.Material.Metal, Enum.PartType.Ball))
    elseif id == "medkit" then
      local b = p(tool, V(1.2, 0.9, 0.5), CF(0, 0.2, -0.4), RGB(230, 230, 225))
      weld(h, b)
      weld(h, p(tool, V(0.6, 0.18, 0.52), CF(0, 0.2, -0.4), RGB(210, 40, 40), Enum.Material.Neon))
      weld(h, p(tool, V(0.18, 0.6, 0.52), CF(0, 0.2, -0.4), RGB(210, 40, 40), Enum.Material.Neon))
    elseif id == "repair" then
      weld(h, p(tool, V(0.2, 0.2, 2.0), CF(0, 0.3, -0.9), RGB(150, 150, 155), Enum.Material.Metal))
      weld(h, p(tool, V(0.6, 0.25, 0.5), CF(0, 0.3, -1.9), RGB(150, 150, 155), Enum.Material.Metal))
    elseif id == "c4" or id == "mine" then
      local isMine = id == "mine"
      weld(h, p(tool, isMine and V(1.2, 0.35, 1.2) or V(1.1, 0.5, 0.7), CF(0, 0.2, -0.5), isMine and OLIVE or TAN, Enum.Material.Plastic, isMine and Enum.PartType.Cylinder or nil))
    elseif id == "breach" then
      weld(h, p(tool, V(0.18, 0.18, 3.6), CF(0, -0.2, -1.8) * CFrame.Angles(-0.5, 0, 0), RGB(60, 62, 58), Enum.Material.Metal))
      weld(h, p(tool, V(0.15, 1.3, 1.3), CF(0, -1.25, -3.4) * CFrame.Angles(0, 0, math.pi / 2), RGB(40, 44, 40), Enum.Material.Plastic, Enum.PartType.Cylinder))
      weld(h, p(tool, V(0.5, 0.4, 0.7), CF(0, 0.15, -0.3), RGB(200, 170, 60), Enum.Material.Plastic))
    elseif id == "binoc" then
      for s = -1, 1, 2 do weld(h, p(tool, V(0.9, 0.35, 0.35), CF(s * 0.22, 0.4, -0.4) * CFrame.Angles(0, math.pi / 2, 0), DARK, Enum.Material.Metal, Enum.PartType.Cylinder)) end
    end
    local a = Instance.new("Attachment")
    a.Name = "Muzzle"
    a.Position = muzzle
    a.Parent = h
    tool.GripPos = V(0, -0.1, 0.3)
    return tool
  end
  -- 两边各一套（真模型按阵营不同：美军 M40A5 + ATACR、AT4、毒刺，解放军 QBU-88、RPG-7、前卫-2）
  local TOOLS = { atk = {}, def = {} }
  for id in pairs(W) do
    TOOLS.atk[id] = makeTool(id, "atk")
    TOOLS.def[id] = makeTool(id, "def")
  end
  G.TOOLS = TOOLS
  -- 部署界面装备格里的小图（客户端 GearView.lua）：两边的工具各放一份样子；导入了原模型的就是原模型
  do
    local prev = Instance.new("Folder")
    prev.Name = "ToolPreview"
    for team, set in pairs(TOOLS) do
      local f = Instance.new("Folder")
      f.Name = team
      for _, t in pairs(set) do t:Clone().Parent = f end
      f.Parent = prev
    end
    prev.Parent = RS
  end

  ---------------------------------------------------------------- 弹药

  local function ammoOf(P, id)
    P.ammo = P.ammo or {}
    local a = P.ammo[id]
    local w = W[id]
    if not a then
      a = { n = w.mag or 1, res = w.reserve, r = 0 }
      P.ammo[id] = a
    end
    if a.r > 0 and now() >= a.r then   -- 换弹好了：从备弹里补
      local need = (w.mag or 1) - a.n
      if a.res then
        local k = math.min(need, a.res)
        a.n += k
        a.res -= k
      else
        a.n += need
      end
      a.r = 0
    end
    return a
  end
  G.ammoOf = ammoOf

  local function startReload(P, id)
    local w = W[id]
    local a = ammoOf(P, id)
    if a.r > 0 or a.n >= (w.mag or 1) then return end
    if a.res and a.res <= 0 then return end
    a.r = now() + (w.reload or 1)
  end
  G.ACT.reload = function(P, id) if W[id] then startReload(P, id) end end

  -- 按兵种发武器（每次出生都重发、弹药补满）
  function G.giveLoadout(P)
    local pl = P.pl
    local kit = G.kitOf(P)   -- 部署时选的装备栏（Round.lua）
    local bp = pl:FindFirstChildOfClass("Backpack") or pl:WaitForChild("Backpack", 5)
    if not bp then return end
    for _, c in ipairs(bp:GetChildren()) do if c:IsA("Tool") then c:Destroy() end end
    P.ammo = {}
    P.placed = {}
    P.cd = {}
    for i, id in ipairs(kit.weapons) do
      local t = (TOOLS[P.team] or TOOLS.def)[id]:Clone()
      t:SetAttribute("Slot", i)
      t.Parent = bp
    end
  end

  ---------------------------------------------------------------- 开火

  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude

  local function src(P) return { P = P, team = P.team, name = P.pl.DisplayName } end

  -- 能不能开火：活着、拿着这把、这个兵种带的、打仗阶段
  local function holding(P, id)
    if not P.alive or not G.round or G.round.phase ~= "battle" then return nil end
    local char = P.char
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local head = char and char:FindFirstChild("Head")
    if not hum or hum.Health <= 0 or not head or P.vehicle then return nil end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool or tool:GetAttribute("Weapon") ~= id then return nil end
    local kit = G.kitOf(P)
    if not kit or not table.find(kit.weapons, id) then return nil end
    return char, head, tool
  end

  local function muzzleOf(tool, head)
    local h = tool:FindFirstChild("Handle")
    local m = h and h:FindFirstChild("Muzzle")
    return m and m.WorldPosition or head.Position
  end

  -- 用掉一发：射速、弹匣；打空了自动换弹
  local function spend(P, id)
    local w = W[id]
    local a = ammoOf(P, id)
    local t = now()
    P.lastShot = P.lastShot or {}
    if t - (P.lastShot[id] or 0) < (w.rate or 0.1) * 0.75 then return false end
    if a.r > 0 then return false end
    if a.n <= 0 then
      startReload(P, id)
      if a.res and a.res <= 0 then G.msg(P.pl, "bad", "ui.outOfAmmo") end
      return false
    end
    P.lastShot[id] = t
    a.n -= 1
    if a.n <= 0 then startReload(P, id) end
    return true
  end

  local function spreadDir(dir, deg)
    if not deg or deg <= 0 then return dir end
    local s = math.rad(deg)
    return (dir + V((math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s)).Unit
  end

  local KIND = {}

  KIND.gun = function(P, id, w, char, head, tool, aim)
    if typeof(aim) ~= "Vector3" or aim.X ~= aim.X then return end
    local origin = head.Position
    local dir = aim - origin
    if dir.Magnitude < 0.5 then return end
    if not spend(P, id) then return end
    dir = spreadDir(dir.Unit, w.spread)
    params.FilterDescendantsInstances = { char }
    local res = workspace:Raycast(origin, dir * w.range, params)
    local hit = res and res.Position or (origin + dir * w.range)
    G.fx({ k = "gun", w = id, a = muzzleOf(tool, head), b = hit, by = P.pl.UserId, q = w.quiet, t = P.team })   -- t：哪一方开的枪（客户端雷达上闪红圈）
    if res and res.Instance then G.hitThing(res.Instance, w, w.dmg, src(P), w.head, res.Position) end
  end

  KIND.proj = function(P, id, w, char, head, tool, aim)
    if typeof(aim) ~= "Vector3" or aim.X ~= aim.X then return end
    local m = muzzleOf(tool, head)
    local dir = aim - m
    if dir.Magnitude < 1 then return end
    if not spend(P, id) then return end
    dir = spreadDir(dir.Unit, w.spread)
    G.launch({ kind = "rocket", pos = m, vel = dir * w.speed, grav = w.drop, w = w, src = src(P), ignore = { char }, life = w.range / w.speed + 1 })
  end

  KIND.throw = function(P, id, w, char, head, tool, aim)
    if typeof(aim) ~= "Vector3" or aim.X ~= aim.X then return end
    if not spend(P, id) then return end
    local m = head.Position + V(0, 0.5, 0)
    local flat = V(aim.X - m.X, 0, aim.Z - m.Z)
    local d = math.min(flat.Magnitude, w.range)
    local dir = (flat.Magnitude > 0.1) and flat.Unit or head.CFrame.LookVector
    local sp = math.clamp(math.sqrt(math.max(1, d) * workspace.Gravity * 0.55), 20, w.speed)   -- 45° 抛出去落在准星附近
    local vel = dir * sp * 0.7071 + V(0, sp * 0.7071, 0)
    G.launch({ kind = "grenade", pos = m, vel = vel, grav = true, fuse = w.fuse, w = w, src = src(P), ignore = { char }, life = w.fuse + 0.5 })
  end

  KIND.lock = function(P, id, w, char, head, tool, tgtId, aim)
    local m = muzzleOf(tool, head)
    local e = (type(tgtId) == "string") and G.entById[tgtId] or nil
    local dir
    if e and e.alive and e.air and e.team ~= P.team and (e.root.CFrame.Position - m).Magnitude <= w.range then
      local to = (e.root.CFrame.Position - m).Unit
      local look = (typeof(aim) == "Vector3") and (aim - head.Position).Unit or to
      if look:Dot(to) < math.cos(math.rad(14)) then e = nil end   -- 锁定要对准（客户端判断过，这里再看一眼）
      dir = to
    else
      e = nil
    end
    if not dir then
      if typeof(aim) ~= "Vector3" then return end
      dir = (aim - m).Unit
    end
    if not spend(P, id) then return end
    G.launch({ kind = "missile", pos = m, vel = dir * w.speed, w = w, src = src(P), ignore = { char }, target = e, life = w.range / w.speed + 2 })
  end

  KIND.mortar = function(P, id, w, char, head, tool, pt)
    if typeof(pt) ~= "Vector3" or pt.X ~= pt.X then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local d = (V(pt.X, 0, pt.Z) - V(hrp.Position.X, 0, hrp.Position.Z)).Magnitude
    if d < w.minR or d > w.maxR then G.msg(P.pl, "bad", "ui.mortarRange", w.minR, w.maxR) return end
    if not spend(P, id) then return end
    local sc = d * 0.025   -- 散布：射程的 2.5%
    local a = math.random() * math.pi * 2
    local x, z = pt.X + math.cos(a) * sc * math.random(), pt.Z + math.sin(a) * sc * math.random()
    G.fx({ k = "mortarFire", p = muzzleOf(tool, head) })
    G.shell(V(x, Map.ground(x, z), z), w, src(P), w.flight + d / 400, hrp.Position)
  end

  KIND.heal = function(P, id, w, char)
    local t = now()
    if t < (P.cd.heal or 0) then return end
    P.cd.heal = t + w.cd
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local healed = 0
    for _, Q in pairs(G.P) do
      if Q.team == P.team and Q.alive and Q.char then
        local h2 = Q.char:FindFirstChild("HumanoidRootPart")
        local hum = Q.char:FindFirstChildOfClass("Humanoid")
        if h2 and hum and hum.Health > 0 and (h2.Position - hrp.Position).Magnitude <= w.r then
          local add = math.min(w.amt, hum.MaxHealth - hum.Health)
          if add > 0 then
            hum.Health += add
            if Q ~= P then healed += add end
            G.msg(Q.pl, "good", "ui.healed", math.floor(add))
          end
        end
      end
    end
    if healed > 0 then G.addScore(P, Config.Score.heal * math.ceil(healed / 25)) end
    G.fx({ k = "heal", p = hrp.Position })
  end

  KIND.repair = function(P, id, w, char, head, tool, entId)
    local e = (type(entId) == "string") and G.entById[entId] or nil
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not e or not e.alive or e.team ~= P.team or not hrp or e.cat == "inf" then return end
    if (e.root.CFrame.Position - hrp.Position).Magnitude > w.range + math.max(e.root.Size.X, e.root.Size.Z) / 2 then return end
    local t = now()
    local dt = math.min(0.5, t - (P.cd.repair or 0))
    P.cd.repair = t
    if dt <= 0.05 or e.hp >= e.maxHp then return end
    local add = math.min(w.rate * dt, e.maxHp - e.hp)
    e.hp += add
    e.model:SetAttribute("Hp", math.floor(e.hp))
    P.repairAcc = (P.repairAcc or 0) + add
    if P.repairAcc >= 100 then
      P.repairAcc -= 100
      G.addScore(P, Config.Score.repair)
    end
    G.fx({ k = "repair", p = e.root.CFrame.Position })
  end

  -- 放东西：炸药包（再用一次引爆）、反坦克地雷（敌方车辆压上去就炸）
  KIND.place = function(P, id, w, char, head, tool, pos)
    P.placed[id] = P.placed[id] or {}
    local list = P.placed[id]
    if id == "c4" and (pos == "det" or (typeof(pos) ~= "Vector3" and #list > 0)) then
      for _, e in ipairs(list) do
        if e.alive then
          G.explode(e.root.CFrame.Position, w, src(P))
          G.removeEnt(e)
        end
      end
      P.placed[id] = {}
      return
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if typeof(pos) ~= "Vector3" or not hrp or (pos - hrp.Position).Magnitude > 12 then
      pos = hrp and (hrp.Position + hrp.CFrame.LookVector * 3) or nil
      if not pos then return end
    end
    if not spend(P, id) then return end
    local y = Map.ground(pos.X, pos.Z)
    local e = G.newEnt({ kind = id, team = P.team, cat = "fort", hp = 30, size = V(1.2, 0.5, 1.2), cf = CF(pos.X, y + 0.25, pos.Z) })
    e.owner = P
    if id == "mine" then
      e.step = function(self)
        for _, x in ipairs(G.ents) do
          if x.alive and x.team ~= self.team and (x.cat == "light" or x.cat == "armor") and not x.air and not x.sea then
            if (x.root.CFrame.Position - self.root.CFrame.Position).Magnitude < 7 + x.root.Size.X / 2 then
              G.explode(self.root.CFrame.Position, w, src(P))
              G.removeEnt(self)
              return
            end
          end
        end
      end
      G.msg(P.pl, "info", "ui.minePlaced")
    else
      G.msg(P.pl, "info", "ui.c4placed")
    end
    table.insert(list, e)
  end

  -- 望远镜：准星附近 4° 以内、看得见的敌人标记 12 秒给全队看；b = "strike" 时呼叫炮火覆盖准星下的地面
  local spotted = { atk = {}, def = {} }
  G.spotted = spotted
  KIND.spot = function(P, id, w, char, head, tool, aim, mode)
    if typeof(aim) ~= "Vector3" or aim.X ~= aim.X then return end
    local t = now()
    if mode == "strike" then
      if t < (P.cd.strike or 0) then G.msg(P.pl, "bad", "ui.strikeCd", math.ceil(P.cd.strike - t)) return end
      P.cd.strike = t + w.strikeCd
      local S = w.strike
      local x0, z0 = aim.X, aim.Z
      for i = 1, S.n do
        task.delay((i - 1) * 0.45, function()
          local a, r = math.random() * math.pi * 2, math.sqrt(math.random()) * S.r
          local x, z = x0 + math.cos(a) * r, z0 + math.sin(a) * r
          G.shell(V(x, Map.ground(x, z), z), S, src(P), S.flight)
        end)
      end
      G.msgTeam(P.team, "info", "ui.strikeCalled", S.flight)
      return
    end
    if t < (P.cd.spot or 0) then return end
    P.cd.spot = t + w.cd
    local o = head.Position
    local look = (aim - o).Unit
    local list = {}
    local function consider(pos, key)
      local to = pos - o
      local d = to.Magnitude
      if d < 4 or d > w.range or to.Unit:Dot(look) < math.cos(math.rad(4)) then return end
      params.FilterDescendantsInstances = { char }
      local res = workspace:Raycast(o, to * 0.98, params)
      if res and (res.Position - pos).Magnitude > 6 then return end
      spotted[P.team][key] = t + w.spotTime
      table.insert(list, key)
    end
    for _, Q in pairs(G.P) do
      if Q.team ~= P.team and Q.alive and Q.char then
        local h2 = Q.char:FindFirstChild("HumanoidRootPart")
        if h2 then consider(h2.Position, "p" .. Q.pl.UserId) end
      end
    end
    for _, e in ipairs(G.ents) do
      if e.alive and e.team ~= P.team and e.team then consider(e.root.CFrame.Position, e.id) end
    end
    if #list > 0 then
      G.addScore(P, Config.Score.spot * #list)
      G.msg(P.pl, "good", "ui.spotted", #list)
    end
  end

  -- 每半秒把还在标记期里的敌人位置发给那一队
  task.spawn(function()
    while true do
      task.wait(0.5)
      local t = now()
      for team, S in pairs(spotted) do
        local out = {}
        for key, till in pairs(S) do
          if till < t then
            S[key] = nil
          else
            local pos = nil
            if string.sub(key, 1, 1) == "p" then
              for _, Q in pairs(G.P) do
                if "p" .. Q.pl.UserId == key and Q.alive and Q.char and Q.char:FindFirstChild("HumanoidRootPart") then pos = Q.char.HumanoidRootPart.Position end
              end
            else
              local e = G.entById[key]
              if e and e.alive then pos = e.root.CFrame.Position end
            end
            if pos then table.insert(out, pos) else S[key] = nil end
          end
        end
        for pl, Q in pairs(G.P) do
          if Q.team == team then G.R.Fx:FireClient(pl, { { k = "spots", list = out } }) end
        end
      end
    end
  end)

  function G.shoot(P, id, a, b)
    local w = W[id]
    if not w then return end
    local char, head, tool = holding(P, id)
    if not char then return end
    local f = KIND[w.kind] or (G.toolKind and G.toolKind[w.kind])   -- 别的模块登记的（破障器材在 Forts）
    if f then f(P, id, w, char, head, tool, a, b) end
  end

  -- 机器人、工事用的「开一枪」：从 from 打向 to（散布 deg），打中玩家或实体
  function G.botShot(from, to, w, srcInfo, ignore, deg)
    local dir = to - from
    if dir.Magnitude < 1 then return end
    dir = spreadDir(dir.Unit, deg or w.spread)
    params.FilterDescendantsInstances = ignore or {}
    local res = workspace:Raycast(from, dir * (w.range or 500), params)
    local hit = res and res.Position or (from + dir * (w.range or 500))
    G.fx({ k = "gun", w = w.fx or "rifle", a = from, b = hit, t = srcInfo and srcInfo.team })
    if res and res.Instance then G.hitThing(res.Instance, w, w.dmg, srcInfo, w.head or 1, res.Position) end
    return res and res.Instance or nil   -- 打中了什么（机器人用来判断是不是被墙挡着）
  end
end

return Weapons
