-- 暗剑：登岛战（客户端）——第一人称持枪：镜头前一个只有自己看得见的「视图模型」（枪 + Roblox 方块手臂）
--   M4：动作照 FPSAnim（从「M4 - FPS Weapon Animations Pack (v.1)」抽的：拔枪、换弹、空仓换弹），再叠上待机呼吸、走路晃、
--     转镜头时枪滞后一点、每发后坐（枪机往后一下）、开镜（照门、准星对到屏幕正中）、枪口火光
--   别的装备（狙击枪、火箭筒、防空导弹、手雷、急救包、扳手、破障器材、炸药包、望远镜、迫击炮）：同一双方块手臂端着它（工具的零件按比例缩小装上去），
--     姿势用 M4 的待机，拔出来往上抬、换弹往下沉、开火后坐都是程序化的
--   枪用动作包里的真 M4：ReplicatedStorage.Imported.FPS_M4 里有导入的 MeshPart（models/fps_m4.glb）就用它们；没有就用 FPSMesh 里嵌的网格和贴图
--     开局在后台用 EditableMesh / EditableImage 生成（不用手动导入）；这两样都用不了（比如没在游戏设置里打开 Mesh / Image API）时才退回零件拼的 M4
--   手臂：袖子是自己角色的身体颜色（队伍迷彩），手掌是手套色；方块形，跟 Roblox 的胳膊一样
--   Play 调：G.fpsFire(武器) 开了一枪、G.fpsReload(武器, 秒数, 空仓) 换弹；G.fpsMuzzle() 枪口在哪（曳光从这儿出去）
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local FPSView = {}

function FPSView.init(G)
  local A = require(RS:WaitForChild("FPSAnim"))
  local W = G.Config.Weapons
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local MAT = Enum.Material
  local CYL = Enum.PartType.Cylinder
  local ALONG = CFrame.Angles(0, math.pi / 2, 0)   -- 圆柱的轴转到 Z
  local now = os.clock

  ---------------------------------------------------------------- 动作数据 → CFrame

  local function quatCF(x, y, z, qx, qy, qz, qw)
    local xx, yy, zz = qx * qx, qy * qy, qz * qz
    local xy, xz, yz = qx * qy, qx * qz, qy * qz
    local wx, wy, wz = qw * qx, qw * qy, qw * qz
    return CFrame.fromMatrix(V(x, y, z), V(1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy)),
      V(2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx)), V(2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy)))
  end
  local CLIP = {}
  for name, c in pairs(A.clips) do
    local T = {}
    for k, arr in pairs(c.t) do
      local list = {}
      for i = 0, #arr / 7 - 1 do
        local o = i * 7
        list[i + 1] = quatCF(arr[o + 1], arr[o + 2], arr[o + 3], arr[o + 4], arr[o + 5], arr[o + 6], arr[o + 7])
      end
      T[k] = list
    end
    CLIP[name] = { fps = c.fps, n = c.n, dur = c.dur, t = T }
  end
  -- 某段动作在 t 秒时某条轨道的 CFrame（两帧之间插值）
  local function sample(clip, k, t)
    local list = clip.t[k] or CLIP.Idle.t[k]
    if #list == 1 then return list[1] end
    local f = math.clamp(t * clip.fps, 0, #list - 1)
    local i = math.floor(f)
    local a = f - i
    if i >= #list - 1 then return list[#list] end
    return list[i + 1]:Lerp(list[i + 2], a)
  end

  ---------------------------------------------------------------- 零件版 M4（在各零件骨骼的坐标系里：+Z 朝枪口、+Y 朝上，单位格）

  local BLACK, DARK, MAGC, BRASS = RGB(38, 38, 40), RGB(50, 50, 52), RGB(58, 58, 60), RGB(196, 160, 72)
  local M4PARTS = {
    -- { 跟哪条轨道, 中心, 尺寸, 颜色, 绕 X 转（度）, 圆柱 }
    { "gun", V(0.005, 0.05, 1.14), V(0.05, 0.05, 0.56), BLACK, 0, true },      -- 枪管
    { "gun", V(0.005, 0.05, 1.43), V(0.066, 0.066, 0.14), DARK, 0, true },     -- 消焰器
    { "gun", V(0.005, 0.07, 0.94), V(0.05, 0.16, 0.14), BLACK },              -- 准星座（导气箍）
    { "gun", V(0.005, 0.205, 0.975), V(0.024, 0.09, 0.03), BLACK },           -- 准星柱
    { "gun", V(0.005, 0.055, 0.58), V(0.17, 0.17, 0.56), DARK },              -- 护木（四面导轨）
    { "gun", V(0.005, 0.045, 0.06), V(0.13, 0.19, 0.48), BLACK },             -- 上机匣
    { "gun", V(0.005, 0.15, 0.08), V(0.085, 0.025, 0.44), DARK },             -- 顶上导轨
    { "gun", V(0.005, 0.185, -0.14), V(0.05, 0.15, 0.08), BLACK },            -- 照门（机械瞄具）
    { "gun", V(0.005, 0.125, -0.21), V(0.12, 0.022, 0.04), DARK },            -- 拉机柄
    { "gun", V(0.005, -0.10, 0.07), V(0.105, 0.20, 0.36), BLACK },            -- 下机匣、弹匣井
    { "gun", V(0.005, -0.19, -0.13), V(0.03, 0.02, 0.2), BLACK },             -- 扳机护圈
    { "gun", V(0.005, -0.28, -0.27), V(0.075, 0.25, 0.10), DARK, 22 },        -- 握把（往后斜）
    { "gun", V(0.005, -0.01, -0.45), V(0.06, 0.06, 0.5), BLACK, 0, true },     -- 缓冲管
    { "gun", V(0.005, -0.05, -0.79), V(0.075, 0.20, 0.34), DARK },            -- 枪托
    { "gun", V(0.005, -0.085, -0.955), V(0.09, 0.40, 0.06), BLACK },          -- 托底板
    { "mag1", V(0, 0, 0), V(0.062, 0.537, 0.24), MAGC, -8 },                  -- 弹匣
    { "mag1", V(0.002, 0.246, -0.028), V(0.05, 0.036, 0.17), BRASS },         -- 最上面那发子弹
    { "mag2", V(0, 0, 0), V(0.062, 0.537, 0.24), MAGC, -8 },                  -- 换弹时拿出来的新弹匣
    { "bolt", V(0, 0, -0.045), V(0.07, 0.07, 0.27), DARK },                   -- 枪机（从抛壳窗看得见）
    { "catch", V(0.001, 0.017, 0), V(0.012, 0.085, 0.026), BLACK },           -- 空仓挂机
    { "trig", V(0, -0.046, -0.015), V(0.012, 0.086, 0.044), BLACK },          -- 扳机
  }
  local MUZZLE = V(0.005, 0.05, 1.5)                                           -- 枪口（枪身骨骼里）
  local SIGHT_R, SIGHT_F = V(0.005, 0.215, -0.14), V(0.005, 0.215, 0.975)      -- 照门、准星（开镜时连成一条线对准屏幕正中）
  local GRIP = V(0.005, -0.16, -0.22)                                          -- 别的装备装在握把这儿

  ---------------------------------------------------------------- 嵌在游戏里的真 M4：后台用 EditableMesh 生成（FPSMesh 是 base64 的顶点、三角形、贴图）

  local gen = nil          -- [节点名] = MeshPart（生成好的；同时只有一个视图模型在用）
  local genStale = false   -- 刚生成好：视图模型重建一次换上
  local B64 = {}
  do
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, 64 do B64[string.byte(chars, i)] = i - 1 end
  end
  local function unb64(s)   -- → 二进制字符串
    local parts, chunk, cn = {}, {}, 0
    local pad = 0
    if string.sub(s, -1) == "=" then pad = (string.sub(s, -2, -2) == "=") and 2 or 1 end
    for i = 1, #s, 4 do
      local a, b, c, d = string.byte(s, i, i + 3)
      local x = B64[a] * 262144 + B64[b] * 4096 + (B64[c] or 0) * 64 + (B64[d] or 0)
      chunk[cn + 1] = math.floor(x / 65536) % 256
      chunk[cn + 2] = math.floor(x / 256) % 256
      chunk[cn + 3] = x % 256
      cn += 3
      if cn >= 3000 then
        parts[#parts + 1] = string.char(table.unpack(chunk, 1, cn))
        cn = 0
      end
    end
    if cn > 0 then parts[#parts + 1] = string.char(table.unpack(chunk, 1, cn)) end
    local out = table.concat(parts)
    if pad > 0 then out = string.sub(out, 1, #out - pad) end
    return out
  end

  local function buildGen()
    local okMod, D = pcall(function() return require(RS:WaitForChild("FPSMesh", 10)) end)
    if not okMod or type(D) ~= "table" then return end
    local AS = game:GetService("AssetService")
    local ok, err = pcall(function()
      local imgs = {}
      for name, t in pairs(D.tex) do
        local rgb = unb64(t.rgb)
        local img = AS:CreateEditableImage({ Size = Vector2.new(t.w, t.h) })
        local buf = buffer.create(t.w * t.h * 4)
        for i = 0, t.w * t.h - 1 do
          local r, g, b = string.byte(rgb, i * 3 + 1, i * 3 + 3)
          buffer.writeu8(buf, i * 4, r)
          buffer.writeu8(buf, i * 4 + 1, g)
          buffer.writeu8(buf, i * 4 + 2, b)
          buffer.writeu8(buf, i * 4 + 3, 255)
          if i % 65536 == 65535 then task.wait() end
        end
        img:WritePixelsBuffer(Vector2.zero, Vector2.new(t.w, t.h), buf)
        imgs[name] = img
        task.wait()
      end
      local out = {}
      for name, nd in pairs(D.nodes) do
        local pos, nrm, uv, idx = unb64(nd.pos), unb64(nd.nrm), unb64(nd.uv), unb64(nd.idx)
        local em = AS:CreateEditableMesh()
        local vid, nid, uid = table.create(nd.n), table.create(nd.n), table.create(nd.n)
        for i = 0, nd.n - 1 do
          local x, y, z = string.unpack("<fff", pos, i * 12 + 1)
          vid[i + 1] = em:AddVertex(V(x, y, z))
          local nx, ny, nz = string.unpack("<bbb", nrm, i * 3 + 1)
          nid[i + 1] = em:AddNormal(V(nx / 127, ny / 127, nz / 127))
          local u, w = string.unpack("<HH", uv, i * 4 + 1)
          uid[i + 1] = em:AddUV(Vector2.new(u / 65535, w / 65535))
        end
        for t = 0, nd.t - 1 do
          local a, b, c = string.unpack("<HHH", idx, t * 6 + 1)
          local f = em:AddTriangle(vid[a + 1], vid[b + 1], vid[c + 1])
          em:SetFaceNormals(f, { nid[a + 1], nid[b + 1], nid[c + 1] })
          em:SetFaceUVs(f, { uid[a + 1], uid[b + 1], uid[c + 1] })
        end
        local mp = AS:CreateMeshPartAsync(Content.fromObject(em))
        mp.Name = name
        mp.Anchored, mp.CanCollide, mp.CanQuery, mp.CanTouch, mp.CastShadow = true, false, false, false, false
        if imgs[nd.mat] then mp.TextureContent = Content.fromObject(imgs[nd.mat]) end
        out[name] = mp
        task.wait()
      end
      gen = out
      genStale = true
    end)
    if not ok then
      warn("[登岛战] 第一人称 M4 的网格生成不了（用零件拼的代替；在 Studio 的游戏设置 → 安全里打开 Mesh / Image API，或者导入 models/fps_m4.glb）：" .. tostring(err))
      G.fpsGenError = tostring(err)
    end
  end
  task.delay(3, buildGen)

  ---------------------------------------------------------------- 方块手臂

  local ARMS = {
    { "rua", 0.30, 0.06 }, { "rfa", 0.27, 0.05 }, { "rh", 0 }, { "lua", 0.30, 0.06 }, { "lfa", 0.27, 0.05 }, { "lh", 0 },
  }
  local GLOVE = RGB(52, 50, 46)

  local function newPart(parent, size, color, mat, shape)
    local p = Instance.new("Part")
    if shape then p.Shape = shape end
    p.Size, p.Color = size, color
    p.Material = mat or MAT.SmoothPlastic
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Parent = parent
    return p
  end

  local function sleeveColor()
    local ch = me.Character
    local bc = ch and ch:FindFirstChildOfClass("BodyColors")
    return bc and bc.RightArmColor3 or RGB(84, 104, 70)
  end

  ---------------------------------------------------------------- 视图模型

  local vm = nil   -- { id, model, items = { { part, track, off } }, kind = "m4" / "item", muzzle = 偏移 }
  G.fps = nil

  local function destroyVM()
    if vm and gen then   -- 生成的网格只有一套：先拿出来，留着下次用
      for _, p in pairs(gen) do if p.Parent == vm.model then p.Parent = nil end end
    end
    if vm then vm.model:Destroy() end
    vm = nil
    G.fps = nil
  end

  -- 导入的原模型（有就用）
  local function importedM4()
    local f = RS:FindFirstChild("Imported")
    local m = f and f:FindFirstChild("FPS_M4")
    if m and m:FindFirstChild("FPS_M4_Main") then return m end
    return nil
  end

  local function buildVM(id, tool)
    destroyVM()
    local model = Instance.new("Model")
    model.Name = "FPSViewModel"
    local items = {}
    local isM4 = id == "m4"
    if isM4 then
      local imp = importedM4()
      if imp then
        for name, info in pairs(A.mesh) do
          local src = imp:FindFirstChild(name)
          if src and src:IsA("BasePart") then
            local p = src:Clone()
            p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
            p.Parent = model
            table.insert(items, { p, info.piece, CF(info.c[1], info.c[2], info.c[3]) })
          end
        end
      end
      if #items == 0 and gen then   -- 嵌在游戏里、开局生成的真 M4
        for name, info in pairs(A.mesh) do
          local p = gen[name]
          if p then
            p.Parent = model
            table.insert(items, { p, info.piece, CF(info.c[1], info.c[2], info.c[3]) })
          end
        end
      end
      if #items == 0 then
        for _, d in ipairs(M4PARTS) do
          local size = d[3]
          local p = newPart(model, d[6] and V(size.Z, size.X, size.Y) or size, d[4], MAT.Metal, d[6] and CYL or nil)
          local off = CF(d[2]) * CFrame.Angles(math.rad(d[5] or 0), 0, 0)
          if d[6] then off = off * ALONG end
          table.insert(items, { p, d[1], off })
        end
      end
    elseif tool then
      -- 工具的零件（焊在把手上的）按 0.75 缩小、装到握把那里（工具的枪口朝 −Z，M4 的枪身骨骼朝 +Z：转 180°）
      local h = tool:FindFirstChild("Handle")
      local K = 0.75
      if h then
        for _, src in ipairs(tool:GetDescendants()) do
          if src:IsA("BasePart") and src ~= h and src.Transparency < 1 then
            local p = src:Clone()
            for _, c in ipairs(p:GetChildren()) do c:Destroy() end
            p.Size = src.Size * K
            p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
            p.Parent = model
            local rel = h.CFrame:ToObjectSpace(src.CFrame)
            local off = CF(GRIP) * CFrame.Angles(0, math.pi, 0) * CF(rel.Position * K) * (rel - rel.Position)
            table.insert(items, { p, "gun", off })
          end
        end
        local mz = h:FindFirstChild("Muzzle")
        model:SetAttribute("Muzzle", true)
        model:SetAttribute("MuzzleOff", mz and mz.Position or V(0, 0.3, -1))
      end
    end
    -- 方块手臂
    local sc = sleeveColor()
    local arms = {}
    for _, a in ipairs(ARMS) do
      local k = a[1]
      local p
      if a[2] == 0 then p = newPart(model, V(0.26, 0.36, 0.13), GLOVE, MAT.Fabric)
      else p = newPart(model, V(a[2], (A.len[k] or 0.7) + a[3], a[2]), sc, MAT.SmoothPlastic) end
      table.insert(arms, { p, k })
    end
    -- 枪口火光
    local flash = newPart(model, V(0.25, 0.25, 0.25), RGB(255, 210, 120), MAT.Neon, Enum.PartType.Ball)
    flash.Transparency = 1
    local light = Instance.new("PointLight")
    light.Brightness, light.Range, light.Color, light.Enabled = 4, 10, RGB(255, 200, 120), false
    light.Parent = flash
    model.Parent = cam
    local mzOff = isM4 and CF(MUZZLE) or nil
    if not isM4 and model:GetAttribute("Muzzle") then
      local mo = model:GetAttribute("MuzzleOff")
      mzOff = CF(GRIP) * CFrame.Angles(0, math.pi, 0) * CF(mo * 0.75)
    end
    vm = { id = id, model = model, items = items, arms = arms, flash = flash, light = light, m4 = isM4, mzOff = mzOff or CF(GRIP),
      plist = {}, clist = {}, act = nil, t0 = now(), draw = now(), flashT = 0, bolt = 0 }
    for _, it in ipairs(items) do table.insert(vm.plist, it[1]) end
    for _, it in ipairs(arms) do table.insert(vm.plist, it[1]) end
    table.insert(vm.plist, flash)
    if isM4 then vm.act = { clip = CLIP.Draw, t0 = now(), speed = 1 } end
    G.fps = vm
  end

  ---------------------------------------------------------------- 开镜：照门、准星连线对到屏幕正中

  local ADS_CF
  do
    local g = CLIP.Idle.t.gun[1]
    local r, f = g * SIGHT_R, g * SIGHT_F
    local dir = (f - r).Unit
    local want = V(0, 0, -1)
    local axis = dir:Cross(want)
    local rot = CFrame.new()
    if axis.Magnitude > 1e-6 then rot = CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(dir:Dot(want), -1, 1))) end
    local target = V(0, 0, -0.34)
    local rr = rot * r
    ADS_CF = CF(target - rr) * rot
  end

  ---------------------------------------------------------------- 事件（Play 调）

  local recoil, recoilV = V(), V()   -- 后坐：x 往后、y 抬头、z 偏航（弹簧）
  function G.fpsFire(id)
    if not vm then return end
    local w = W[id]
    local big = w and (w.kind ~= "gun") or (id == "sniper")
    local k = big and 3 or 1
    recoilV += V(0.9 * k, (0.7 + math.random() * 0.3) * k, (math.random() - 0.5) * 0.6 * k)
    vm.bolt = 1
    vm.flashT = now()
  end
  function G.fpsReload(id, dur, empty)
    if not vm or vm.id ~= id then return end
    if vm.m4 then
      local c = empty and CLIP.Reload_Empty or CLIP.Reload
      vm.act = { clip = c, t0 = now(), speed = c.dur / math.max(0.3, dur or 2.4) }
    else
      vm.reloadT0, vm.reloadDur = now(), dur or 1.5
    end
  end
  function G.fpsMuzzle()
    if vm and vm.mzWorld then return vm.mzWorld end
    return nil
  end

  ---------------------------------------------------------------- 每帧

  local ads, swayX, swayY, swayVX, swayVY = 0, 0, 0, 0, 0
  local lastCam, lastPos, bobPhase, speedS = nil, nil, 0, 0
  local hiddenTool = nil

  local function hideTool(tool, on)
    if not tool then return end
    for _, p in ipairs(tool:GetDescendants()) do
      if p:IsA("BasePart") then p.LocalTransparencyModifier = on and 1 or 0 end
    end
  end

  -- 每帧（Play.stepPlay 之后）：active 拿着装备、第一人称；aiming 开镜
  function G.stepFPS(dt, active, aiming, hide, curTool)
    local ch = me.Character
    local tool = active and ch and ((curTool and curTool.Parent == ch) and curTool or ch:FindFirstChildOfClass("Tool")) or nil
    local id = tool and tool:GetAttribute("Weapon")
    if hiddenTool and hiddenTool ~= tool then hideTool(hiddenTool, false) hiddenTool = nil end
    if not id then
      if vm then destroyVM() end
      return
    end
    if not vm or vm.id ~= id or vm.tool ~= tool or (genStale and vm.m4) then
      genStale = false
      buildVM(id, tool)
      if not vm then return end
      vm.tool = tool
    end
    hideTool(tool, true)
    hiddenTool = tool
    local t = now()
    dt = math.clamp(dt or 1 / 60, 1 / 240, 0.1)
    -- 镜头转动 → 枪滞后（sway）
    local cc = cam.CFrame
    local tx, ty = 0, 0
    if lastCam then   -- 镜头转得越快，枪落后得越多（往反方向偏一点、再弹回来）
      local d = lastCam:ToObjectSpace(cc)
      tx = math.clamp(-d.LookVector.X / dt * 0.012, -0.1, 0.1)
      ty = math.clamp(-d.LookVector.Y / dt * 0.012, -0.1, 0.1)
    end
    lastCam = cc
    swayVX += ((tx - swayX) * 120 - swayVX * 16) * dt
    swayVY += ((ty - swayY) * 120 - swayVY * 16) * dt
    swayX = math.clamp(swayX + swayVX * dt, -0.12, 0.12)
    swayY = math.clamp(swayY + swayVY * dt, -0.12, 0.12)
    -- 走路晃（按人实际移动的速度）
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp then
      local p = hrp.Position
      if lastPos then
        local sp = V(p.X - lastPos.X, 0, p.Z - lastPos.Z).Magnitude / dt
        speedS = speedS + (math.min(sp, 30) - speedS) * math.min(1, dt * 8)
      end
      lastPos = p
    end
    bobPhase += dt * speedS * 0.62
    local walk = math.clamp(speedS / 16, 0, 1.2) * (1 - ads * 0.85)
    -- 后坐弹簧
    recoilV += (-recoil * 180 - recoilV * 18) * dt
    recoil += recoilV * dt
    -- 开镜（换弹、拔枪时不行）
    local busy = vm.act ~= nil and vm.act.clip ~= CLIP.Fire
    local wantAds = (aiming and not busy) and 1 or 0
    ads = ads + (wantAds - ads) * math.min(1, dt * 10)
    -- 当前动作
    local clip, ct = CLIP.Idle, 0
    if vm.act then
      ct = (t - vm.act.t0) * vm.act.speed
      if ct >= vm.act.clip.dur then vm.act = nil else clip = vm.act.clip end
    end
    -- 程序化：呼吸、走路、滞后、后坐；别的装备的拔出、换弹
    local breath = math.sin(t * 1.6) * 0.006 * (1 - ads * 0.7)
    local sw = 1 - ads * 0.6
    local P = CF(math.sin(bobPhase) * 0.035 * walk + swayX * 0.3 * sw, breath - math.abs(math.cos(bobPhase)) * 0.03 * walk + swayY * 0.3 * sw, 0)
      * CFrame.Angles(swayY * 0.5 * sw + math.cos(bobPhase * 2) * 0.006 * walk, -swayX * 0.8 * sw, math.sin(bobPhase) * 0.01 * walk)
    local pivot = CF(0.2, -0.35, -0.6)   -- 后坐绕着握把附近转
    local kick = CF(0, 0, recoil.X) * pivot * CFrame.Angles(recoil.Y * 0.8, recoil.Z * 0.5, 0) * pivot:Inverse()
    local extra = CF()
    if not vm.m4 then
      local da = math.clamp((t - vm.draw) / 0.35, 0, 1)
      extra = CF(0, -(1 - da) ^ 2 * 0.8, 0) * CFrame.Angles(-(1 - da) ^ 2 * 0.6, 0, 0)
      if vm.reloadT0 then
        local r = (t - vm.reloadT0) / vm.reloadDur
        if r >= 1 then vm.reloadT0 = nil else
          local dip = math.sin(math.clamp(r, 0, 1) * math.pi)
          extra = extra * CF(0, -dip * 0.35, 0) * CFrame.Angles(-dip * 0.35, 0, dip * 0.4)
        end
      end
    end
    local adsCF = CF():Lerp(ADS_CF, ads)
    local base = cc * P * kick * extra * adsCF
    -- 枪的零件
    local clist = vm.clist
    local n = 0
    vm.bolt = math.max(0, vm.bolt - dt * 14)
    for _, it in ipairs(vm.items) do
      local tr = it[2]
      local cf = sample(clip, tr, ct)
      if tr == "bolt" and vm.bolt > 0 then cf = cf * CF(0, 0, -0.12 * math.sin(vm.bolt * math.pi)) end
      n += 1
      clist[n] = base * cf * it[3]
    end
    for _, it in ipairs(vm.arms) do
      n += 1
      clist[n] = base * sample(clip, it[2], ct)
    end
    -- 枪口、火光
    local gunCF = base * sample(clip, "gun", ct)
    local mz = gunCF * vm.mzOff
    vm.mzWorld = mz.Position
    local fl = t - vm.flashT < 0.05
    n += 1
    clist[n] = mz * CFrame.Angles(math.random() * 6.28, 0, 0)
    vm.flash.Transparency = fl and 0.15 or 1
    vm.light.Enabled = fl
    for i = n + 1, #clist do clist[i] = nil end
    workspace:BulkMoveTo(vm.plist, clist, Enum.BulkMoveMode.FireCFrameChanged)
    -- 狙击镜、望远镜放大时整个藏起来
    local hideAll = hide == true
    if vm.hidden ~= hideAll then
      vm.hidden = hideAll
      for _, p in ipairs(vm.plist) do p.LocalTransparencyModifier = hideAll and 1 or 0 end
    end
  end

  -- 不是第一人称了（死了、上车、第三人称）：收起来
  function G.fpsOff()
    if hiddenTool then hideTool(hiddenTool, false) hiddenTool = nil end
    destroyVM()
    lastCam, lastPos = nil, nil
  end
end

return FPSView
