-- Roblox全面大战场（客户端）——地图自带工事的样子：机枪碉堡、岸防炮、高炮、M777 榴弹炮，零件拼的；
--   炮塔、炮管按属性 Ty / Gp 平滑地转（自己在操作的用本地的），开炮后坐，被毁时顶板塌下来、发黑、冒火冒烟；队伍色小旗（据点被拿下换颜色）
--   走到自己队的工事旁出现「E 操作」提示、走到自己队的空车旁出现「E 上车」（ProximityPrompt：手机点一下、手柄按键也行）
--   G.solidAt(点, 半径)：开车时撞上工事、钢刺猬就停（Drive.lua 调）
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local FortView = {}

function FortView.init(G)
  local FD = require(RS:WaitForChild("FortDefs"))
  local Map = G.Map
  local Config = G.Config
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local MAT = Enum.Material
  local CYL = Enum.PartType.Cylinder
  local me = Players.LocalPlayer
  local UP = CFrame.Angles(0, 0, math.pi / 2)      -- 圆柱的轴转到 Y（竖着的圆盘）
  local ALONG = CFrame.Angles(0, math.pi / 2, 0)   -- 圆柱的轴转到 Z（炮管）
  local function T(k, ...) return G.T(k, ...) end

  local CONC, CONC2, DARK, GUN = RGB(156, 152, 140), RGB(128, 126, 118), RGB(22, 22, 24), RGB(46, 48, 50)
  local OLIVE, OLIVE2, GREY, SOD = RGB(88, 98, 68), RGB(70, 80, 56), RGB(120, 126, 128), RGB(92, 116, 66)

  local function newPart(m, size, color, mat, shape)
    local x = Instance.new("Part")
    if shape then x.Shape = shape end
    x.Size, x.Color = size, color
    x.Material = mat or MAT.SmoothPlastic
    x.Anchored, x.CanCollide, x.CanQuery, x.CanTouch = true, false, false, false
    x.TopSurface, x.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    x.CastShadow = size.Magnitude > 3
    x.Parent = m
    return x
  end

  ---------------------------------------------------------------- 零件：每个 { 零件, 组（hull 不动 / turret 跟炮塔转 / gun 跟炮管俯仰 / roof 被毁时塌）, 偏移 }

  local BUILD = {}
  -- add(组, 尺寸, 偏移, 颜色, 材质, 形状)；炮管 barrel(组, 长, 粗, 偏移, 颜色)
  BUILD.bunker = function(add, barrel)
    add("hull", V(16.4, 0.8, 14.4), CF(0, 0.4, 0), CONC, MAT.Concrete)
    add("hull", V(16, 6.2, 1.6), CF(0, 3.9, 6.2), CONC, MAT.Concrete)       -- 后墙
    add("hull", V(1.6, 6.2, 11), CF(-7.2, 3.9, 0), CONC, MAT.Concrete)      -- 两侧墙
    add("hull", V(1.6, 6.2, 11), CF(7.2, 3.9, 0), CONC, MAT.Concrete)
    add("hull", V(16, 3.2, 1.8), CF(0, 2.4, -6.1), CONC, MAT.Concrete)      -- 射孔下沿（射孔高 4.0～5.2）
    add("hull", V(13, 1.2, 0.3), CF(0, 4.6, -4.9), DARK)                    -- 射孔里面黑的
    add("hull", V(2, 1.2, 1.8), CF(-7, 4.6, -6.1), CONC, MAT.Concrete)
    add("hull", V(2, 1.2, 1.8), CF(7, 4.6, -6.1), CONC, MAT.Concrete)
    add("hull", V(16, 1.6, 1.8), CF(0, 6.0, -6.1), CONC, MAT.Concrete)      -- 射孔上沿
    add("hull", V(3, 4.4, 0.3), CF(0, 3.0, 7.05), RGB(70, 60, 50), MAT.Wood)   -- 后门
    add("roof", V(17.6, 1.0, 15.6), CF(0, 7.3, -0.2), CONC2, MAT.Concrete)  -- 顶板
    add("roof", V(15, 0.9, 12.4), CF(0, 8.2, 0.4), SOD, MAT.Grass)          -- 顶上覆土
    -- 12.7 毫米机枪：机匣、枪管、提把、枪架
    add("gun", V(0.9, 0.9, 1.9), CF(0, 0, 0.75), GUN, MAT.Metal)
    barrel("gun", 4.4, 0.32, CF(0, 0.05, -2.2), GUN)
    add("gun", V(0.2, 0.35, 0.8), CF(0, 0.6, 0.3), GUN, MAT.Metal)
    add("turret", V(0.35, 1.0, 0.35), CF(0, -0.85, 0.8), GUN, MAT.Metal)
    return V(6.2, 8.7, 5.4)   -- 小旗的位置
  end
  BUILD.coastal = function(add, barrel)
    add("hull", V(1.2, 23, 23), CF(0, 0.6, 0) * UP, CONC2, MAT.Concrete, CYL)   -- 炮位底座
    for k = 1, 9 do   -- 一圈矮墙（后面留入口）
      local a = k * math.pi / 5
      add("hull", V(7.6, 3.2, 1.6), CF(math.sin(a) * 12.2, 2.4, math.cos(a) * 12.2) * CFrame.Angles(0, a, 0), CONC, MAT.Concrete)
    end
    add("turret", V(1.2, 9.6, 9.6), CF(0, -0.9, 0) * UP, GUN, MAT.Metal, CYL)    -- 座圈
    add("turret", V(8.6, 4.6, 8.4), CF(0, 1.9, 1.6), GREY, MAT.Metal)            -- 炮塔（Mk 45 式）
    add("turret", V(8.0, 3.6, 4.4), CF(0, 1.3, -3.6) * CFrame.Angles(math.rad(26), 0, 0), GREY, MAT.Metal)   -- 前面的斜面
    add("turret", V(1.6, 1.0, 1.6), CF(2.6, 4.6, 2.4), GUN, MAT.Metal)            -- 顶上的观察镜
    barrel("gun", 3.2, 1.8, CF(0, 0, -1.4), GREY)                                 -- 炮根护套
    barrel("gun", 20, 0.95, CF(0, 0, -10), GUN)
    return V(9.5, 6.5, 9.5)
  end
  BUILD.aaa = function(add, barrel)
    add("hull", V(8, 0.8, 8), CF(0, 0.6, 0), OLIVE, MAT.Metal)
    for k = 0, 3 do   -- 四条支腿、垫板
      local a = math.pi / 4 + k * math.pi / 2
      local c, s = math.cos(a), math.sin(a)
      add("hull", V(0.7, 0.5, 6.4), CF(c * 4.6, 0.35, s * 4.6) * CFrame.Angles(0, -a + math.pi / 2, 0), OLIVE2, MAT.Metal)
      add("hull", V(1.5, 0.3, 1.5), CF(c * 7.6, 0.15, s * 7.6), DARK, MAT.Metal)
    end
    add("turret", V(1.0, 5.2, 5.2), CF(0, -1.0, 0) * UP, OLIVE2, MAT.Metal, CYL)   -- 转盘
    add("turret", V(4.4, 2.2, 4.4), CF(0, 0.4, 0.6), OLIVE, MAT.Metal)             -- 炮架
    add("turret", V(1.3, 2.0, 3.6), CF(-2.9, 0.9, 0.2), OLIVE, MAT.Metal)          -- 两侧弹仓
    add("turret", V(1.3, 2.0, 3.6), CF(2.9, 0.9, 0.2), OLIVE, MAT.Metal)
    add("turret", V(1.4, 1.2, 1.4), CF(0, 1.1, 2.6), DARK, MAT.Metal)              -- 炮手座、瞄具
    add("gun", V(3.8, 0.9, 2.4), CF(0, 0, 0.4), OLIVE, MAT.Metal)                  -- 摇架
    for s = -1, 1, 2 do
      barrel("gun", 7.6, 0.42, CF(s * 1.5, 0, -3.8), GUN)
      barrel("gun", 0.9, 0.62, CF(s * 1.5, 0, -7.4), DARK)                           -- 消焰器
    end
    return V(4.5, 5.5, 4.5)
  end
  BUILD.howitzer = function(add, barrel)
    for s = -1, 1, 2 do   -- 大架：两条往后叉开，尾巴上驻锄
      add("hull", V(0.9, 0.7, 11), CF(s * 2.1, 0.55, 5.8) * CFrame.Angles(0, s * 0.3, 0), OLIVE, MAT.Metal)
      add("hull", V(1.8, 1.2, 0.4), CF(s * 3.8, 0.45, 10.9) * CFrame.Angles(0, s * 0.3, 0), DARK, MAT.Metal)
      add("hull", V(0.9, 2.6, 2.6), CF(s * 2.6, 1.3, 1.4), DARK, MAT.Rubber, CYL)  -- 车轮
    end
    add("hull", V(4.2, 1.0, 4.2), CF(0, 0.5, 0.6), OLIVE, MAT.Metal)               -- 座盘
    add("hull", V(2.2, 1.1, 1.3), CF(5.2, 0.55, 6.5), RGB(112, 92, 62), MAT.Wood)  -- 弹药箱
    add("hull", V(2.2, 1.1, 1.3), CF(5.6, 1.65, 6.6), RGB(112, 92, 62), MAT.Wood)
    add("net", V(16, 0.25, 22), CF(0, 7.6, 2), OLIVE2, MAT.Fabric)                  -- 伪装网
    add("turret", V(3.2, 1.8, 3.4), CF(0, -0.5, 0), OLIVE, MAT.Metal)              -- 上架
    add("turret", V(0.4, 2.6, 2.6), CF(-1.7, 0.2, -0.2), OLIVE, MAT.Metal)
    add("turret", V(0.4, 2.6, 2.6), CF(1.7, 0.2, -0.2), OLIVE, MAT.Metal)
    barrel("gun", 14.5, 0.7, CF(0, 0, -6.6), OLIVE2)
    add("gun", V(1.6, 1.1, 1.4), CF(0, 0, -14.1), DARK, MAT.Metal)                -- 炮口制退器
    add("gun", V(1.3, 1.3, 1.8), CF(0, 0, 1.0), OLIVE, MAT.Metal)                 -- 炮闩
    for s = -1, 1, 2 do barrel("gun", 6, 0.45, CF(s * 0.38, -0.65, -2.8), GUN) end -- 反后坐装置
    return V(6.5, 8.6, 7.5)
  end

  ---------------------------------------------------------------- 建、动

  local views = {}   -- [实体编号] = v（工事的）
  local function angDiff(a, b) return (b - a + 180) % 360 - 180 end

  local function teamCol(team) return (Config.Teams[team or "def"] or Config.Teams.def).color end

  local function build(v, em, team)
    local kind = em:GetAttribute("Model")
    local d = FD.D[kind or ""]
    local mk = BUILD[kind or ""]
    if not d or not mk then return false end
    local m = Instance.new("Model")
    m.Name = "Fort_" .. kind
    local list = {}
    local function add(grp, size, off, color, mat, shape)
      local part = newPart(m, size, color, mat, shape)
      if grp == "net" then part.Transparency = 0.35 grp = "hull" end
      table.insert(list, { part, grp, off })
      return part
    end
    local function barrel(grp, len, dia, off, color)
      return add(grp, V(len, dia, dia), off * ALONG, color, MAT.Metal, CYL)
    end
    local flagAt = mk(add, barrel)
    -- 队伍色小旗
    add("hull", V(0.2, 4.2, 0.2), CF(flagAt + V(0, -2.1, 0)), RGB(200, 200, 196), MAT.Metal)
    v.flag = add("hull", V(2.6, 1.5, 0.12), CF(flagAt + V(1.35, -0.5, 0)), teamCol(team), MAT.Fabric)
    -- 血条挂点、走过去的提示挂点
    local anchor = newPart(m, V(0.2, 0.2, 0.2), RGB(0, 0, 0))
    anchor.Transparency = 1
    local manA = newPart(m, V(0.4, 0.4, 0.4), RGB(0, 0, 0))
    manA.Transparency = 1
    v.model, v.anchor, v.manA = m, anchor, manA
    v.fd, v.fkind, v.parts = d, kind, list
    v.ty, v.gp, v.recoil = em:GetAttribute("Ty") or 0, em:GetAttribute("Gp") or 0, 0
    v.dirty = true
    v.plist, v.clist = {}, {}
    for i, it in ipairs(list) do v.plist[i] = it[1] end
    local pr = Instance.new("ProximityPrompt")
    pr.ActionText = T("ui.man")
    pr.ObjectText = T("fort." .. kind)
    pr.KeyboardKeyCode = Enum.KeyCode.E
    pr.HoldDuration = 0
    pr.MaxActivationDistance = 12
    pr.RequiresLineOfSight = false
    pr.Enabled = false
    pr.Parent = manA
    pr.Triggered:Connect(function() G.R.Act:FireServer("enterVeh", v.id) end)
    v.prompt = pr
    views[v.id] = v
    return true
  end

  local function wreckIt(v)
    v.wrecked = true
    for _, it in ipairs(v.parts) do
      local part = it[1]
      part.Color = part.Color:Lerp(Color3.new(0.05, 0.05, 0.05), 0.6)
    end
    if v.flag then v.flag.Transparency = 1 end
    local holder = v.anchor
    local fire = Instance.new("Fire")
    fire.Size, fire.Heat = 9, 12
    fire.Parent = holder
    local smoke = Instance.new("Smoke")
    smoke.Color, smoke.Opacity, smoke.RiseVelocity, smoke.Size = RGB(40, 40, 40), 0.6, 6, 8
    smoke.Parent = holder
    task.delay(40, function() if fire.Parent then fire.Enabled = false end end)
    v.dirty = true
  end

  local function step(v, dt, camPos)
    local em = v.em
    local root = v.root
    local d = v.fd
    local base = root.CFrame * CF(0, -d.size.Y / 2, 0)
    -- 队伍（据点被攻方拿下后这处工事归攻方）
    local team = em:GetAttribute("Team")
    if team ~= v.team then
      v.team = team
      if v.flag then v.flag.Color = teamCol(team) end
      if v.fill then v.fill.BackgroundColor3 = teamCol(team) end
    end
    if em:GetAttribute("Wreck") and not v.wrecked then wreckIt(v) end
    -- 炮塔、炮管：自己操作的用本地的，别人的平滑跟属性
    local own = G.gunner and G.gunner.id == v.id and G.gunner
    local ty, gp = em:GetAttribute("Ty") or 0, em:GetAttribute("Gp") or 0
    if v.wrecked then ty, gp = v.ty, d.turret.elev[1] - 8 end
    local oty, ogp = v.ty, v.gp
    if own then v.ty, v.gp = own.ty, own.gp else
      local k = math.min(1, dt * 8)
      v.ty = v.ty + angDiff(v.ty, ty) * k
      v.gp = v.gp + (gp - v.gp) * k
    end
    if v.recoil > 0 then v.recoil = math.max(0, v.recoil - dt * 2.2) v.dirty = true end
    local moved = math.abs(angDiff(oty, v.ty)) > 0.02 or math.abs(ogp - v.gp) > 0.02
    -- 离得远、没动：不用重摆
    if not v.dirty and not moved then return end
    if not v.dirty and (base.Position - camPos).Magnitude > 2200 then return end
    v.dirty = false
    local tF = base * CF(d.turret.pivot) * CFrame.Angles(0, -math.rad(v.ty), 0)
    local kick = (v.fkind == "howitzer") and 2.4 or ((v.fkind == "coastal") and 1.6 or 0.5)
    local gF = tF * CF(d.gun.pivot) * CFrame.Angles(math.rad(v.gp), 0, 0) * CF(0, 0, v.recoil * kick)
    local roofF = base
    if v.wrecked then roofF = base * CF(0, -1.6, 0.4) * CFrame.Angles(0.16, 0, 0.07) end
    local plist, clist = v.plist, v.clist
    for i, it in ipairs(v.parts) do
      local grp, off = it[2], it[3]
      if grp == "turret" then clist[i] = tF * off
      elseif grp == "gun" then clist[i] = gF * off
      elseif grp == "roof" then clist[i] = roofF * off
      else clist[i] = base * off end
    end
    workspace:BulkMoveTo(plist, clist, Enum.BulkMoveMode.FireCFrameChanged)
    v.anchor.CFrame = base * CF(0, d.size.Y + 2, 0)
    v.manA.CFrame = base * CF(FD.MAN[v.fkind])
  end

  local function recoil(v) v.recoil = 1 v.dirty = true end
  local function remove(v) views[v.id] = nil end

  G.viewKind = G.viewKind or {}
  G.viewKind.fort = { build = build, step = step, recoil = recoil, remove = remove }

  ---------------------------------------------------------------- 走过去的提示（工事、空车），每 0.25 秒更新一次

  local promptT = 0
  local function myAlive()
    local ch = me.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0 and not G.drive
  end
  function G.stepForts(dt)
    promptT -= dt
    if promptT > 0 then return end
    promptT = 0.25
    local side = me:GetAttribute("Side")
    local ok = myAlive() and G.S and G.S.alive and not (G.S.veh)
    for _, v in pairs(views) do
      local em = v.em
      if v.prompt then
        v.prompt.Enabled = (ok and em.Parent ~= nil and em:GetAttribute("Team") == side and (em:GetAttribute("Gunner") or 0) == 0
          and not em:GetAttribute("Wreck") and (em:GetAttribute("Hp") or 0) > 0) and true or false
      end
    end
    -- 地面载具、飞机：自己队的、没人开的（运输直升机有人开也能坐后面）
    for em, v in pairs(G.views or {}) do
      if (v.kind == "veh" or v.kind == "air") and v.anchor then
        if not v.prompt then
          local pr = Instance.new("ProximityPrompt")
          pr.ActionText = T("ui.board")
          pr.ObjectText = T("veh." .. (v.def and v.def.id or ""))
          pr.KeyboardKeyCode = Enum.KeyCode.E
          pr.HoldDuration = 0
          local d = v.def
          pr.MaxActivationDistance = (v.kind == "air") and math.max(14, math.max(d and d.L or 10, d and d.W or 10) * 0.5 + 8)
            or math.max(12, (d and d.L or 10) * 0.6 + 6)
          pr.RequiresLineOfSight = false
          pr.Parent = v.anchor
          pr.Triggered:Connect(function() G.R.Act:FireServer("enterVeh", v.id) end)
          v.prompt = pr
        end
        local free = (em:GetAttribute("Driver") or 0) == 0 or (v.kind == "air" and v.def and v.def.transport)
        v.prompt.Enabled = (ok and em:GetAttribute("Team") == side and free and not em:GetAttribute("Wreck")
          and not em:GetAttribute("Locked")) and true or false
      end
    end
  end

  ---------------------------------------------------------------- 撞上工事、钢刺猬（开车用）

  local hogs = {}
  do
    local ok, ob = pcall(FD.obstacles, Map)
    if ok and ob then hogs = ob.hog end
  end
  local HOG_R = 2.6
  function G.solidAt(p, r)
    for _, v in pairs(views) do
      local root = v.root
      if root and root.Parent then
        local l = root.CFrame:PointToObjectSpace(p)
        local s = root.Size
        if math.abs(l.X) < s.X / 2 + r and math.abs(l.Z) < s.Z / 2 + r and math.abs(l.Y) < s.Y / 2 + 8 then return true end
      end
    end
    for _, h in ipairs(hogs) do
      local dx, dz = h.x - p.X, h.z - p.Z
      local rr = HOG_R + r
      if dx * dx + dz * dz < rr * rr then return true end
    end
    return false
  end
  G.fortViews = views
end

return FortView
