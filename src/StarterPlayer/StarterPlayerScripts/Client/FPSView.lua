-- Roblox全面大战场（客户端）——第一人称持枪：镜头前一个只有自己看得见的「视图模型」（枪 + Roblox 方块手臂）
--   M4：动作照 FPSAnim（从「M4 - FPS Weapon Animations Pack (v.1)」抽的：拔枪、换弹、空仓换弹），再叠上待机呼吸、走路晃、
--     转镜头时枪滞后一点、每发后坐（枪机往后一下）、开镜（照门、准星对到屏幕正中）、枪口火光
--   别的装备（狙击枪、火箭筒、防空导弹、手雷、急救包、扳手、破障器材、炸药包、望远镜、迫击炮）：同一双方块手臂端着它（工具的零件按比例缩小装上去），
--     姿势用 M4 的待机，拔出来往上抬、换弹往下沉、开火后坐都是程序化的
--   枪用动作包里的真 M4：ReplicatedStorage.Imported.FPS_M4 里有导入的 MeshPart（models/fps_m4.glb）就用它们；没有就用 FPSMesh 里嵌的网格和贴图
--     开局在后台用 EditableMesh / EditableImage 生成（不用手动导入）；这两样都用不了（比如没在游戏设置里打开 Mesh / Image API）时才退回零件拼的 M4
--   手臂：袖子是自己角色的身体颜色（队伍迷彩），手掌是手套色；方块形，跟 Roblox 的胳膊一样
--   狙击枪、望远镜换上 Sketchfab 的真模型（Optics.lua：狙击镜是 Nightforce ATACR、望远镜原样）：开镜时整个举到眼前，镜子的光轴对正屏幕中心、
--     目镜越来越近；眼睛贴上目镜（ads > 0.9）以后才把模型藏起来，屏幕上换成 Scope.lua 画的目镜里的像（G.fpsOpticPending 告诉它还在举）
--   Play 调：G.fpsFire(武器) 开了一枪、G.fpsReload(武器, 秒数, 空仓) 换弹；G.fpsMuzzle() 枪口在哪（曳光从这儿出去）
--   改枪（用户 11-20，GunMods.lua）：工具的 Build 属性里装的配件按 GM.m4Mount 装到 M4 上——枪口件套在消焰器上（枪口跟着往前挪）、
--     换瞄具（机械瞄具 / 红点 / 全息 / 3.5 倍 / 6 倍；红点、全息开镜看着枪，屏幕上照光轴画一个红点 / 全息圈，只在窗口里看得见）、
--     握把在护木下面、弹匣换掉两个弹匣骨骼上的原装弹匣、战术件在右侧导轨（激光：一道看得见的光打到前面；手电：一盏聚光灯）；
--     狙击枪的枪口件装在真模型的枪口。开镜快慢按操控速度（w.adsSpd）、晃动按据枪稳定性（w.swayK），装了消音器枪口焰很淡
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Tint = require(script.Parent:WaitForChild("Tint"))   -- 导入的贴图没出来时的底色（原贴图的平均色）
local TURN = require(RS:WaitForChild("ImportTurn")).TURN   -- 导入的每块网格被 Roblox 转了半圈（ImportTurn.lua）：摆的时候转回来

local FPSView = {}

function FPSView.init(G)
  local A = require(RS:WaitForChild("FPSAnim"))
  local GD = require(RS:WaitForChild("GearDefs"))
  local GM = require(RS:WaitForChild("GunMods"))
  local W = G.W or G.Config.Weapons   -- 自己的枪按装的配件（GunKit.lua）
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
  -- 真模型的器材（Optics.lua）装在枪身骨骼的哪儿：狙击镜的镜座底面贴在零件拼的枪身顶面（工具里 y 0.55 × 0.75），目镜在握把上方；
  --   望远镜原点在两个目镜中间，右手拿着；skip 不要工具里哪些零件（零件拼的镜子 / 望远镜）
  local OPTIC = {
    sniper = { key = "atacr", at = CF(0.005, 0.2525, 0.35), skip = "^Scope" },
    binoc = { key = "binoc", at = CF(GRIP + V(0, 0.18, 0.06)), skip = "." },
  }
  -- M4 上机匣的皮卡汀尼导轨（真模型量的：z −0.05～0.85 一段平的，顶面 y 0.142）上装一具 ACOG：镜座底面贴导轨，目镜在照门前面
  --   （照门 z −0.25～−0.10、比光轴高一点，眼睛贴上目镜时它在眼睛后面）
  local M4_OPTIC = { key = "acog", at = CF(0, 0.142, 0.24) }

  -- 改枪的配件模型（Optics.lua 的真模型）装到视图模型上：off 是器材原点在这条骨骼里的位置；还在现生成时返回 false（调用的地方记下来等）
  local function addAtt(model, items, key, off, track, keep)
    local op = G.opticParts and G.opticParts(key)
    if not op then return false end
    for _, x in ipairs(op) do
      x.part.Parent = model
      local gt = GM.glassT(key, x.name)
      if gt then x.part.Transparency = gt end   -- 镜片、窗玻璃：看得穿
      table.insert(items, { x.part, track, off * x.cf, optic = keep and x.name or nil })
    end
    return true
  end
  local function waitFor(list, key)
    if G.opticFailed and G.opticFailed(key) then return list end
    list = list or {}
    table.insert(list, key)
    return list
  end

  -- 整件真模型（工具属性 Gear = 键、GearMount = 枪上的镜子，GearDefs）：握把放在 M4 握把那儿（再挪 fpOff、按 hold 转），镜子装在枪的导轨上；
  --   导入的或者现生成的（Optics.lua）都还没有时返回 nil 和要等的键（先用工具上零件拼的，生成好了重建）
  local function gearVM(model, items, key, mountKey)
    local M = G.opticMeta and G.opticMeta[key]
    if not M or not G.opticParts then return nil, nil end
    local MM = mountKey and G.opticMeta[mountKey]
    if mountKey and not MM then mountKey = nil end
    local op = G.opticParts(key)
    local mp = mountKey and G.opticParts(mountKey)
    local need = {}
    if not op then table.insert(need, key) end
    if mountKey and not mp then table.insert(need, mountKey) end
    if #need > 0 then return nil, need end
    local at = CF(GRIP + GD.fpOff(key, M)) * GD.grip(M)
    -- 开镜时一直看得见的块（optic）：望远镜、枪上装的镜子；镜子和枪是一整块的（QBU-88）整支都算
    local whole = key == "binoc" or (M.eye ~= nil and not mountKey)
    for _, x in ipairs(op) do
      x.part.Parent = model
      table.insert(items, { x.part, "gun", at * x.cf, optic = whole and x.name or nil })
    end
    local E, ea = M, at
    if mp then
      E, ea = MM, at * GD.mountAt(key, M)
      for _, x in ipairs(mp) do
        x.part.Parent = model
        table.insert(items, { x.part, "gun", ea * x.cf, optic = x.name })
      end
    end
    local info = nil
    if key == "binoc" then
      info = { kind = "binoc", eyeG = at * V(), objG = at * V(0, 0, 0.5), r = 0.03 }
    elseif E.eye and E.obj then
      info = { kind = "scope", eyeG = ea * V(E.eye.c[1], E.eye.c[2], E.eye.c[3]), objG = ea * V(E.obj.c[1], E.obj.c[2], E.obj.c[3]), r = E.eye.r }
    end
    local mz = GD.muzzle(M)
    return { optic = info, mz = mz and (at * CF(mz)) or nil }, nil
  end
  local function allReady(keys)
    if not G.opticReady then return false end
    for _, k in ipairs(keys) do
      if not G.opticReady(k) then return false end
    end
    return true
  end

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
      warn("[全面大战场] 第一人称 M4 的网格生成不了（用零件拼的代替；在 Studio 的游戏设置 → 安全里打开 Mesh / Image API，或者导入 models/fps_m4.glb）：" .. tostring(err))
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
    if G.reflexStep then G.reflexStep(nil, nil, false) end
  end

  -- 导入的原模型（有就用）
  local function importedM4()
    local f = RS:FindFirstChild("Imported")
    local m = f and f:FindFirstChild("FPS_M4")
    if m and m:FindFirstChild("FPS_M4_Main") then return m end
    return nil
  end

  local MAG_MESH = { FPS_M4_Mag1 = true, FPS_M4_Mag2 = true }   -- 原装弹匣（换了弹匣就不装；最上面那发子弹留着）
  -- 待机姿势里某条骨骼在枪身骨骼坐标里的位置（改枪界面装弹匣用）
  function G.m4Track(track)
    return sample(CLIP.Idle, "gun", 0):Inverse() * sample(CLIP.Idle, track, 0)
  end
  -- 部署界面装备格的小图：整支 M4（导入的或现生成的），按待机姿势摆好，枪身骨骼坐标（+Z 朝枪口）；都还没有返回 nil
  --   noMag：不要原装弹匣（改枪界面换了弹匣）
  function G.m4Model(noMag)
    local imp = importedM4()
    local g0 = sample(CLIP.Idle, "gun", 0):Inverse()
    local m, n = Instance.new("Model"), 0
    for name, info in pairs(A.mesh) do
      local p = (imp and imp:FindFirstChild(name)) or (gen and gen[name])
      if p and info.piece ~= "mag2" and not (noMag and MAG_MESH[name]) then   -- 换弹时手里那个新弹匣不要
        local fromImp = imp and imp:FindFirstChild(name) == p
        local q = p:Clone()
        if fromImp then Tint.fix(q, p) end
        q.Anchored, q.CanCollide, q.CanQuery, q.CanTouch = true, false, false, false
        q.CFrame = g0 * sample(CLIP.Idle, info.piece, 0) * CF(info.c[1], info.c[2], info.c[3]) * (fromImp and TURN or CF())
        q.Parent = m
        n += 1
      end
    end
    if n == 0 then m:Destroy() return nil end
    return m
  end

  local function buildVM(id, tool)
    destroyVM()
    local opticInfo, vm0Wait, realMz = nil, nil, nil
    local model = Instance.new("Model")
    model.Name = "FPSViewModel"
    local items = {}
    local isM4 = id == "m4"
    -- 改枪：这把枪装的配件（工具的 Build 属性；没有就是默认的）
    local bld = GM.has(id) and GM.clean(id, GM.decode(tool and tool:GetAttribute("Build"))) or nil
    local mzM4, tac = MUZZLE, nil
    local magIt = isM4 and bld and GM.ITEM[bld.mag]
    local magKey = magIt and magIt.model
    local skipMag = magKey ~= nil and G.opticReady ~= nil and G.opticReady(magKey)   -- 换的弹匣模型好了才拿掉原装的
    if magKey and not skipMag then
      if G.opticParts then G.opticParts(magKey) end   -- 开始现生成
      vm0Wait = waitFor(vm0Wait, magKey)
    end
    if isM4 then
      local imp = importedM4()
      if imp then
        for name, info in pairs(A.mesh) do
          local src = imp:FindFirstChild(name)
          if src and src:IsA("BasePart") and not (skipMag and MAG_MESH[name]) then
            local p = Tint.fix(src:Clone(), src)
            p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
            p.Parent = model
            table.insert(items, { p, info.piece, CF(info.c[1], info.c[2], info.c[3]) * TURN })   -- 导入的：补回转掉的半圈
          end
        end
      end
      if #items == 0 and gen then   -- 嵌在游戏里、开局生成的真 M4
        for name, info in pairs(A.mesh) do
          local p = gen[name]
          if p and not (skipMag and MAG_MESH[name]) then
            p.Parent = model
            table.insert(items, { p, info.piece, CF(info.c[1], info.c[2], info.c[3]) })
          end
        end
      end
      local partsM4 = #items == 0
      if partsM4 then
        for _, d in ipairs(M4PARTS) do
          if not (skipMag and (d[1] == "mag1" or d[1] == "mag2") and d[4] == MAGC) then   -- 换了弹匣：零件拼的弹匣不要
            local size = d[3]
            local p = newPart(model, d[6] and V(size.Z, size.X, size.Y) or size, d[4], MAT.Metal, d[6] and CYL or nil)
            local off = CF(d[2]) * CFrame.Angles(math.rad(d[5] or 0), 0, 0)
            if d[6] then off = off * ALONG end
            table.insert(items, { p, d[1], off })
          end
        end
      end
      -- 导轨上的 ACOG（用户：武器瞄准没有镜子）：开镜时光轴对正屏幕中心、目镜举到眼前，贴上以后换成 Scope.lua 画的目镜里的像
      --   零件拼的 M4 导轨顶面高一点（0.1625）。改枪换了瞄具的走下面那段
      local railK = partsM4 and CF(0, 0.1625 - 0.142, 0) or CF()
      local oi = bld and GM.ITEM[bld.optic]
      if bld and bld.optic ~= "acog" then
        if oi and oi.model and G.opticMeta and G.opticMeta[oi.model] then
          local M = G.opticMeta[oi.model]
          local mt = GM.m4Mount(bld.optic, M)
          local at = railK * mt.cf
          if addAtt(model, items, oi.model, at, "gun", true) then
            local sg = GM.sightOf(bld.optic, M)
            if sg then opticInfo = { kind = oi.scope and "scope" or "dot", dot = oi.dot, eyeG = at * sg.eye, objG = at * sg.obj, r = sg.r, adsD = oi.adsD } end
            if mt.riser then   -- 增高座：迷你红点垫高到和别的瞄具差不多的高度（不然照门挡着）
              local rp = newPart(model, V(0.058, mt.riser, 0.1), RGB(34, 34, 36), MAT.Metal)
              table.insert(items, { rp, "gun", at * CF(0, -mt.riser / 2, 0.01), optic = "Riser" })
            end
          else
            vm0Wait = waitFor(vm0Wait, oi.model)
          end
        end
      elseif G.opticMeta and G.opticMeta[M4_OPTIC.key] then
        local op = G.opticParts and G.opticParts(M4_OPTIC.key)
        local at = partsM4 and (CF(0, 0.1625 - 0.142, 0) * M4_OPTIC.at) or M4_OPTIC.at
        if op then
          local M = G.opticMeta[M4_OPTIC.key]
          for _, x in ipairs(op) do
            x.part.Parent = model
            table.insert(items, { x.part, "gun", at * x.cf, optic = x.name })
          end
          opticInfo = { kind = "scope", eyeG = at * V(M.eye.c[1], M.eye.c[2], M.eye.c[3]), objG = at * V(M.obj.c[1], M.obj.c[2], M.obj.c[3]), r = M.eye.r }
        elseif not (G.opticFailed and G.opticFailed(M4_OPTIC.key)) then
          vm0Wait = waitFor(vm0Wait, M4_OPTIC.key)   -- 还在生成：先用光秃秃的 M4，生成好了重建
        end
      end
      -- 枪口、握把、战术件、弹匣（GunMods.m4Mount 量好的位置）
      for _, slot in ipairs({ "muzzle", "grip", "tac", "mag" }) do
        local it = bld and GM.ITEM[bld[slot]]
        local M = it and it.model and G.opticMeta and G.opticMeta[it.model]
        local mt = M and GM.m4Mount(bld[slot], M)
        if mt then
          if slot == "mag" then
            if skipMag then
              addAtt(model, items, it.model, mt.cf, "mag1")
              addAtt(model, items, it.model, mt.cf, "mag2")
            end
          elseif addAtt(model, items, it.model, mt.cf, "gun") then
            if mt.mz then mzM4 = mt.mz end   -- 消音器、补偿器：枪口往前挪到它的前端
            if slot == "tac" then   -- 激光的出光口 / 手电的灯头（器材坐标里前端面中心）
              tac = { kind = it.laser and "laser" or "light", off = mt.cf * CF(0, (M.size and M.size[2] or 0.12) / 2, (M.size and M.size[3] or 0.38) / 2) }
            end
          else
            vm0Wait = waitFor(vm0Wait, it.model)
          end
        end
      end
    elseif tool then
      local gk = tool:GetAttribute("Gear")
      local gr, need = nil, nil
      if gk then gr, need = gearVM(model, items, gk, tool:GetAttribute("GearMount")) end
      if gr then   -- 整件真模型
        opticInfo = gr.optic
        realMz = gr.mz or CF(GRIP)
        local it = bld and GM.ITEM[bld.muzzle]
        local M = it and it.model and G.opticMeta and G.opticMeta[it.model]
        if M and gr.mz then   -- 改枪：狙击枪的枪口件（后端往枪管里套一点）
          local at = gr.mz * CF(0, 0, -0.03)
          if addAtt(model, items, it.model, at, "gun") then
            realMz = at * CF(0, 0, (M.size and M.size[3]) or 0.3)
          else
            vm0Wait = waitFor(vm0Wait, it.model)
          end
        end
      else
      if need then vm0Wait = need end
      -- 工具的零件（焊在把手上的）按 0.75 缩小、装到握把那里（工具的枪口朝 −Z，M4 的枪身骨骼朝 +Z：转 180°）
      local h = tool:FindFirstChild("Handle")
      local K = 0.75
      local OD = OPTIC[id]
      local op = OD and G.opticParts and G.opticParts(OD.key)   -- 真模型（还没生成好时是 nil，先用零件拼的，生成好了下一帧重建）
      if OD and not op and not vm0Wait then vm0Wait = { OD.key } end
      if h then
        for _, src in ipairs(tool:GetDescendants()) do
          if src:IsA("BasePart") and src ~= h and src.Transparency < 1 and not (op and string.match(src.Name, OD.skip)) then
            local p = src:Clone()
            for _, c in ipairs(p:GetChildren()) do
              if not c:IsA("SurfaceAppearance") then c:Destroy() end   -- 导入的块带着贴图：留着
            end
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
      if op then
        local M = G.opticMeta and G.opticMeta[OD.key]
        for _, x in ipairs(op) do
          x.part.Parent = model
          table.insert(items, { x.part, "gun", OD.at * x.cf, optic = x.name })
        end
        local eye = M and M.eye
        local obj = M and M.obj
        opticInfo = {
          kind = (id == "binoc") and "binoc" or "scope",
          eyeG = OD.at * (eye and V(eye.c[1], eye.c[2], eye.c[3]) or V()),
          objG = OD.at * (obj and V(obj.c[1], obj.c[2], obj.c[3]) or V(0, 0, 0.5)),
          r = eye and eye.r or 0.03,
        }
      end
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
    local mzOff = isM4 and CF(mzM4) or realMz
    if not isM4 and not realMz and model:GetAttribute("Muzzle") then
      local mo = model:GetAttribute("MuzzleOff")
      mzOff = CF(GRIP) * CFrame.Angles(0, math.pi, 0) * CF(mo * 0.75)
    end
    -- 战术件：激光（一道细光 + 打到的地方一个亮点）、手电（聚光灯）
    local beam, spot, lamp = nil, nil, nil
    if tac and tac.kind == "laser" then
      beam = newPart(model, V(0.01, 0.01, 1), RGB(255, 40, 30), MAT.Neon)
      beam.Transparency = 0.25
      spot = newPart(model, V(0.12, 0.12, 0.12), RGB(255, 60, 40), MAT.Neon, Enum.PartType.Ball)
      spot.Transparency = 0.1
    elseif tac and tac.kind == "light" then
      lamp = newPart(model, V(0.05, 0.05, 0.05), RGB(255, 255, 255), MAT.SmoothPlastic)
      lamp.Transparency = 1
      local sl = Instance.new("SpotLight")
      sl.Brightness, sl.Range, sl.Angle, sl.Face, sl.Shadows = 4, 80, 38, Enum.NormalId.Front, false
      sl.Color = RGB(255, 246, 228)
      sl.Parent = lamp
    end
    vm = { id = id, model = model, items = items, arms = arms, flash = flash, light = light, m4 = isM4, mzOff = mzOff or CF(GRIP),
      plist = {}, clist = {}, act = nil, t0 = now(), draw = now(), flashT = 0, bolt = 0, optic = opticInfo, wait = vm0Wait,
      tac = tac, beam = beam, spot = spot, lamp = lamp }
    for _, it in ipairs(items) do table.insert(vm.plist, it[1]) end
    for _, it in ipairs(arms) do table.insert(vm.plist, it[1]) end
    table.insert(vm.plist, flash)
    if beam then   -- 激光、亮点、手电的灯：排在火光后面（每帧按这个顺序摆）
      table.insert(vm.plist, beam)
      table.insert(vm.plist, spot)
    elseif lamp then
      table.insert(vm.plist, lamp)
    end
    local wv = W[id]
    vm.quiet = wv and wv.quiet == true
    if isM4 then vm.act = { clip = CLIP.Draw, t0 = now(), speed = math.sqrt((wv and wv.adsSpd) or 1) } end   -- 拔枪快慢：操控速度（改枪）
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

  -- 真模型器材的开镜位置：目镜中心、物镜中心连线（光轴）转到镜头正前方，目镜放在 d 处——
  --   瞄准镜：d 让目镜在屏幕上占高度的 86%（视角越小推得越远，放大时看起来一样大）；望远镜：两个目镜贴到眼前
  local function opticAds(O)
    local g = CLIP.Idle.t.gun[1]
    local r, f = g * O.eyeG, g * O.objG
    local dir = (f - r).Unit
    local want = V(0, 0, -1)
    local axis = dir:Cross(want)
    local rot = CFrame.new()
    if axis.Magnitude > 1e-6 then rot = CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(dir:Dot(want), -1, 1))) end
    local d = 0.22
    if O.kind == "scope" then d = math.max(0.14, O.r / (math.tan(math.rad(cam.FieldOfView) / 2) * 0.86))
    elseif O.kind == "dot" then d = O.adsD or 0.3 end   -- 红点、全息（改枪）：后窗离眼睛 0.2～0.45 格，看得见枪和窗框
    return CF(V(0, 0, -d) - rot * r) * rot
  end

  ---------------------------------------------------------------- 事件（Play 调）

  local recoil, recoilV = V(), V()   -- 后坐：x 往后、y 抬头、z 偏航（弹簧）
  function G.fpsFire(id)
    if not vm then return end
    local w = W[id]
    local big = w and (w.kind ~= "gun") or (id == "sniper")
    local k = (big and 3 or 1) * 0.7   -- 用户：后坐稍微调低一点（枪往后坐、往上抬都比原来小三成）
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

  ---------------------------------------------------------------- 红点、全息的分划（改枪）

  -- 反射式瞄具的分划在无穷远：沿光轴很远的一点投到屏幕上就是红点的位置（枪晃，点跟着窗口一起晃）；
  --   只在窗口里看得见（窗口中心是前窗，半径照投影算）。T1 / Romeo3 一个红点带一圈晕，EXPS3 全息是 65 MOA 的圈 + 中心 1 MOA 的点
  local ret = nil
  local function retGui()
    if ret then return ret end
    local gui = Instance.new("ScreenGui")
    gui.Name = "ReflexReticle"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = -2
    gui.Enabled = false
    gui.Parent = me:WaitForChild("PlayerGui")
    local function circ(color, tr)
      local f = Instance.new("Frame")
      f.AnchorPoint = Vector2.new(0.5, 0.5)
      f.BackgroundColor3 = color
      f.BackgroundTransparency = tr
      f.BorderSizePixel = 0
      local c = Instance.new("UICorner")
      c.CornerRadius = UDim.new(0.5, 0)
      c.Parent = f
      f.Parent = gui
      return f
    end
    local glow = circ(RGB(255, 60, 40), 0.8)
    local dot = circ(RGB(255, 74, 52), 0)
    local ring = circ(RGB(255, 60, 40), 1)
    local st = Instance.new("UIStroke")
    st.Color, st.Thickness, st.Transparency = RGB(255, 74, 52), 2, 0.05
    st.Parent = ring
    ret = { gui = gui, glow = glow, dot = dot, ring = ring, st = st }
    return ret
  end
  function G.reflexStep(v, gunCF, on)
    if not on or not v or not v.optic then
      if ret then ret.gui.Enabled = false end
      return
    end
    local R = retGui()
    local O = v.optic
    local eye, obj = gunCF * O.eyeG, gunCF * O.objG
    local dir = (obj - eye).Unit
    local p = cam:WorldToViewportPoint(obj + dir * 500)
    local c = cam:WorldToViewportPoint(obj)
    local vs = cam.ViewportSize
    local k = vs.Y / 1080
    local dist = (obj - cam.CFrame.Position).Magnitude
    local rpx = (O.r or 0.05) / math.max(0.05, dist) * (vs.Y / 2) / math.tan(math.rad(cam.FieldOfView) / 2)
    local inside = p.Z > 0 and Vector2.new(p.X - c.X, p.Y - c.Y).Magnitude < rpx * 0.92
    R.gui.Enabled = inside
    if not inside then return end
    local holo = O.dot == "holo"
    local ds = math.max(2, math.floor((holo and 3 or 4.5) * k + 0.5))
    R.dot.Size = UDim2.fromOffset(ds, ds)
    R.dot.Position = UDim2.fromOffset(p.X, p.Y)
    R.glow.Size = UDim2.fromOffset(ds * 3.2, ds * 3.2)
    R.glow.Position = UDim2.fromOffset(p.X, p.Y)
    R.ring.Visible = holo
    if holo then
      local rs = math.floor(46 * k + 0.5)
      R.ring.Size = UDim2.fromOffset(rs, rs)
      R.ring.Position = UDim2.fromOffset(p.X, p.Y)
      R.st.Thickness = math.max(1.5, 2 * k)
    end
    local nv = G.nvgOn and G.nvgOn()   -- 开着夜视仪：调暗
    R.dot.BackgroundTransparency = nv and 0.45 or 0
    R.glow.BackgroundTransparency = nv and 0.92 or 0.8
  end

  ---------------------------------------------------------------- 每帧

  local ads, swayX, swayY, swayVX, swayVY = 0, 0, 0, 0, 0
  -- 还在把镜子举到眼前（Scope.lua 开着镜时问；等举到了才画目镜里的像。Play 每帧先调 Scope、后调 stepFPS，所以不看这一帧按没按右键）
  function G.fpsOpticPending()
    return vm ~= nil and vm.optic ~= nil and vm.optic.kind ~= "dot" and ads < 0.88
  end
  local lastCam, lastPos, bobPhase, speedS, latS = nil, nil, 0, 0, 0
  local hiddenTool = nil
  local waitTries = setmetatable({}, { __mode = "k" })   -- [工具] = 等真模型、因为「好了」重建过几次
  local badTool = setmetatable({}, { __mode = "k" })     -- [工具] = 建视图模型出过错（不再重建）

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
    local opticNow = vm and vm.wait and allReady(vm.wait)   -- 真模型（整件、瞄准镜、望远镜）刚生成好
    if opticNow then   -- 说好了却还是拿不到的：最多重建 3 次，别每一帧都重建（切到火箭筒卡住就是这样）
      local n = (waitTries[vm.tool or vm] or 0) + 1
      waitTries[vm.tool or vm] = n
      if n > 3 then
        vm.wait, opticNow = nil, false
      end
    end
    if not vm or vm.id ~= id or vm.tool ~= tool or (genStale and vm.m4) or opticNow then
      genStale = false
      -- 建视图模型出错（导入的零件少块、器材坐标对不上……）：这件工具记下来，不再每一帧重建（用户：切到 2 号武器就卡住），
      --   改用工具上零件拼的样子；只报一次
      if badTool[tool] then
        if vm and vm.tool ~= tool then destroyVM() end
        if not vm then return end
      else
        local ok, err = pcall(buildVM, id, tool)
        if not ok then
          badTool[tool] = true
          destroyVM()
          warn("[全面大战场] 第一人称 " .. tostring(id) .. " 建不起来，用第三人称的样子代替：" .. tostring(err))
          return
        end
        if not vm then return end
        vm.tool = tool
      end
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
      -- 记录仪观感（用户：持枪参考 bodycam）：枪更沉，转镜头时落后得更多
      tx = math.clamp(-d.LookVector.X / dt * 0.017, -0.14, 0.14)
      ty = math.clamp(-d.LookVector.Y / dt * 0.017, -0.14, 0.14)
    end
    lastCam = cc
    swayVX += ((tx - swayX) * 120 - swayVX * 16) * dt
    swayVY += ((ty - swayY) * 120 - swayVY * 16) * dt
    swayX = math.clamp(swayX + swayVX * dt, -0.16, 0.16)
    swayY = math.clamp(swayY + swayVY * dt, -0.16, 0.16)
    -- 走路晃（按人实际移动的速度）
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp then
      local p = hrp.Position
      if lastPos then
        local dv = V(p.X - lastPos.X, 0, p.Z - lastPos.Z) / dt
        local sp = dv.Magnitude
        speedS = speedS + (math.min(sp, 30) - speedS) * math.min(1, dt * 8)
        latS = latS + (math.clamp(cc.RightVector:Dot(dv) / 16, -1.2, 1.2) - latS) * math.min(1, dt * 6)   -- 横着走：枪往那边歪
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
    local wv = W[vm.id]
    ads = ads + (wantAds - ads) * math.min(1, dt * 10 * ((wv and wv.adsSpd) or 1))   -- 开镜快慢：操控速度（改枪：握把、瞄具、弹匣都有影响）
    -- 当前动作
    local clip, ct = CLIP.Idle, 0
    if vm.act then
      ct = (t - vm.act.t0) * vm.act.speed
      if ct >= vm.act.clip.dur then vm.act = nil else clip = vm.act.clip end
    end
    -- 程序化：呼吸、走路、滞后、后坐；别的装备的拔出、换弹
    local swayK = (wv and wv.swayK) or 1   -- 据枪稳定性（改枪）
    local breath = math.sin(t * 1.6) * 0.006 * (1 - ads * 0.7) * swayK
    local sw = 1 - ads * 0.6
    local P = CF(math.sin(bobPhase) * 0.05 * walk + swayX * 0.3 * sw, breath - math.abs(math.cos(bobPhase)) * 0.045 * walk + swayY * 0.3 * sw, 0)
      * CFrame.Angles(swayY * 0.5 * sw + math.cos(bobPhase * 2) * 0.009 * walk, -swayX * 0.8 * sw, math.sin(bobPhase) * 0.022 * walk - latS * 0.07 * sw)
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
    local adsT = ADS_CF
    if vm.optic then adsT = opticAds(vm.optic) end
    local adsCF = CF():Lerp(adsT, ads)
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
    vm.flash.Transparency = fl and (vm.quiet and 0.88 or 0.15) or 1   -- 装了消音器：只有一丝
    vm.light.Enabled = fl and not vm.quiet
    -- 战术件（改枪）：激光从出光口沿枪管方向打出去，打到哪儿哪儿一个亮点；手电的灯跟着灯头
    if vm.tac then
      local tcf = gunCF * vm.tac.off
      vm.tacWorld = tcf
      if vm.beam then
        local o = tcf.Position
        local dir = gunCF.LookVector
        local rp = G.fpsRay or RaycastParams.new()
        G.fpsRay = rp
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = { vm.model, ch }
        local hit = workspace:Raycast(o, dir * 300, rp)
        local e = hit and hit.Position or (o + dir * 300)
        local L = (e - o).Magnitude
        vm.beam.Size = V(0.008, 0.008, L)
        vm.beam.Transparency = 0.25 + ads * 0.5   -- 开着镜淡一点（光正对着眼睛）
        n += 1
        clist[n] = CFrame.lookAt(o + dir * (L / 2), e)
        n += 1
        clist[n] = CFrame.new(e - dir * 0.05)
        vm.spot.Transparency = hit and 0.1 or 1
      elseif vm.lamp then
        n += 1
        clist[n] = tcf
      end
    end
    for i = n + 1, #clist do clist[i] = nil end
    workspace:BulkMoveTo(vm.plist, clist, Enum.BulkMoveMode.FireCFrameChanged)
    -- 狙击镜、望远镜放大时整个藏起来；真模型的：举镜过程中只留镜子本身（视角收窄了，枪身、手臂会大得出奇），眼睛贴上目镜才整个藏
    local hideAll = hide == true
    vm.aimNow = aiming == true
    G.reflexStep(vm, gunCF, aiming == true and vm.optic ~= nil and vm.optic.kind == "dot" and ads > 0.82)
    if vm.optic and vm.optic.kind ~= "dot" then
      hideAll = hide == true and aiming == true and ads > 0.9
      local only = aiming == true and ads > 0.35
      if vm.onlyOptic ~= only or vm.hidden ~= hideAll then
        vm.onlyOptic, vm.hidden = only, hideAll
        local keep = {}
        for _, it in ipairs(vm.items) do if it.optic and it.optic ~= "Reticle" then keep[it[1]] = true end end
        for _, p in ipairs(vm.plist) do p.LocalTransparencyModifier = (hideAll or (only and not keep[p])) and 1 or 0 end
      end
    elseif vm.hidden ~= hideAll then
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
