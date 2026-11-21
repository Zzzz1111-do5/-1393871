-- Roblox全面大战场（客户端）——瞄准镜、望远镜的真模型（Sketchfab 上的原模型，几何和贴图原样）：给第一人称（FPSView）用
--   有导入的（Studio 里导入 models/optics/<键>.glb，Imports.lua 收进 ReplicatedStorage.Imported.Optics.<键>，带原来的 PBR 贴图）就用它；
--   没有就用 OpticMesh/<键> 里嵌的网格和底色贴图，开局在后台用 EditableMesh / EditableImage 生成（要在游戏设置 → 安全里打开 Mesh / Image API）；
--   两样都没有时 G.opticParts 返回 nil，FPSView 照旧用零件拼的
--   G.opticParts(键) → { { name 块名, part 复制出来的 MeshPart, c 块中心（器材坐标） }, … }；G.opticMeta = OpticsMeta（目镜、物镜的位置和半径）
local RS = game:GetService("ReplicatedStorage")
local Tint = require(script.Parent:WaitForChild("Tint"))   -- 导入的贴图没出来时的底色（原贴图的平均色）
local TURN = require(RS:WaitForChild("ImportTurn")).TURN   -- 导入的每块网格被 Roblox 转了半圈（ImportTurn.lua）

local Optics = {}

function Optics.init(G)
  local okM, META = pcall(function() return require(RS:WaitForChild("OpticsMeta", 5)) end)
  if not okM or type(META) ~= "table" then return end
  G.opticMeta = META
  local V = Vector3.new

  local B64 = {}
  do
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, 64 do B64[string.byte(chars, i)] = i - 1 end
  end
  local function unb64(s)
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

  local function quiet(p)
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    return p
  end

  -- 导入的：ReplicatedStorage.Imported.Optics.<键> 里 O_<键>__<块名>
  local function imported(key)
    local f = RS:FindFirstChild("Imported")
    f = f and f:FindFirstChild("Optics")
    f = f and f:FindFirstChild(key)
    if not f then return nil end
    local n = f:GetAttribute("N")   -- 块还没全复制过来：先当没导入（不然拿到缺块的枪）
    if n and #f:GetChildren() < n then return nil end
    for name in pairs(META[key].parts) do   -- 元数据里的块缺了（瞄准镜拆出镜筒里面的块以后没重新导入）：用现生成的
      if not f:FindFirstChild("O_" .. key .. "__" .. name) then return nil end
    end
    local list = {}
    for name, info in pairs(META[key].parts) do
      local src = f:FindFirstChild("O_" .. key .. "__" .. name)
      if src and src:IsA("BasePart") then
        local c = V(info.c[1], info.c[2], info.c[3])
        table.insert(list, { name = name, src = src, c = c, cf = CFrame.new(c) * TURN })   -- 导入的：补回转掉的半圈
      end
    end
    return (#list > 0) and list or nil
  end

  -- 嵌在游戏里的：后台生成一次，之后复制
  local gen, busy, failed = {}, {}, {}
  local running = 0   -- 正在现生成的件数：一次只生成一件（几件一起生成，手机上那几秒会掉帧、看着像卡住）
  local function build(key)
    if gen[key] or busy[key] or failed[key] then return end
    busy[key] = true
    task.spawn(function()
      while running > 0 do task.wait(0.1) end
      running += 1
      local ok, err = pcall(function()
        local D = require(RS:WaitForChild("OpticMesh", 5):WaitForChild(key, 5))
        local AS = game:GetService("AssetService")
        local list = {}
        for name, d in pairs(D.parts) do
          local pos = unb64(d.pos) task.wait()   -- 大件解码一段让一帧
          local nrm = unb64(d.nrm) task.wait()
          local uv = unb64(d.uv) task.wait()
          local idx = unb64(d.idx) task.wait()
          local b, ub = d.b, d.ub
          local em = AS:CreateEditableMesh()
          local vid, nid, uid = table.create(d.n), table.create(d.n), table.create(d.n)
          for i = 0, d.n - 1 do
            local qx, qy, qz = string.unpack("<HHH", pos, i * 6 + 1)
            vid[i + 1] = em:AddVertex(V(b[1] + (b[4] - b[1]) * qx / 65535, b[2] + (b[5] - b[2]) * qy / 65535, b[3] + (b[6] - b[3]) * qz / 65535))
            local nx, ny, nz = string.unpack("<bbb", nrm, i * 3 + 1)
            nid[i + 1] = em:AddNormal(V(nx / 127, ny / 127, nz / 127))
            local u, w = string.unpack("<HH", uv, i * 4 + 1)
            uid[i + 1] = em:AddUV(Vector2.new(ub[1] + (ub[3] - ub[1]) * u / 65535, ub[2] + (ub[4] - ub[2]) * w / 65535))
            if i % 1500 == 1499 then task.wait() end   -- 一帧少做一点：在战斗里现生成也不掉帧
          end
          for t = 0, d.t - 1 do
            local a, b2, c = string.unpack("<HHH", idx, t * 6 + 1)
            local f = em:AddTriangle(vid[a + 1], vid[b2 + 1], vid[c + 1])
            em:SetFaceNormals(f, { nid[a + 1], nid[b2 + 1], nid[c + 1] })
            em:SetFaceUVs(f, { uid[a + 1], uid[b2 + 1], uid[c + 1] })
            if t % 1500 == 1499 then task.wait() end
          end
          local mp = quiet(AS:CreateMeshPartAsync(Content.fromObject(em)))
          mp.Name = "O_" .. key .. "__" .. name
          mp.Material = Enum.Material.SmoothPlastic
          mp.Color = Color3.fromRGB(d.col[1], d.col[2], d.col[3])
          if d.tex then   -- 调色板贴图 → EditableImage
            local pal, px = unb64(d.tex.pal), unb64(d.tex.px)
            local img = AS:CreateEditableImage({ Size = Vector2.new(d.tex.w, d.tex.h) })
            local n = d.tex.w * d.tex.h
            local buf = buffer.create(n * 4)
            for i = 0, n - 1 do
              local k = string.byte(px, i + 1)
              local r, g, bb = string.byte(pal, k * 3 + 1, k * 3 + 3)
              buffer.writeu8(buf, i * 4, r)
              buffer.writeu8(buf, i * 4 + 1, g)
              buffer.writeu8(buf, i * 4 + 2, bb)
              buffer.writeu8(buf, i * 4 + 3, 255)
              if i % 65536 == 65535 then task.wait() end
            end
            img:WritePixelsBuffer(Vector2.zero, Vector2.new(d.tex.w, d.tex.h), buf)
            mp.TextureContent = Content.fromObject(img)
            mp.Color = Color3.new(1, 1, 1)
          end
          local info = META[key].parts[name]
          local c = info and V(info.c[1], info.c[2], info.c[3]) or V()
          table.insert(list, { name = name, src = mp, c = c, cf = CFrame.new(c) })   -- 现生成的网格方向本来就对
          task.wait()
        end
        gen[key] = list
      end)
      running -= 1
      busy[key] = nil
      if not ok then
        failed[key] = true
        warn("[全面大战场] 瞄准镜模型 " .. key .. " 生成不了（用零件拼的代替；在 Studio 的游戏设置 → 安全里打开 Mesh / Image API，或者导入 models/optics/" .. key .. ".glb）：" .. tostring(err))
      end
    end)
  end

  -- 镜筒里面的块（OpticsMeta 的 inner：内壁、镜片、分划板）——第一人称开镜时藏起来，从目镜的洞里直接看放大的画面（使命召唤那样）
  local innerSet = {}
  for key, M in pairs(META) do
    if type(M.inner) == "table" then
      innerSet[key] = {}
      for _, n in ipairs(M.inner) do innerSet[key][n] = true end
    end
  end
  function G.opticInner(key, name) return innerSet[key] ~= nil and innerSet[key][name] == true end

  -- 现生成失败了（没开 Mesh / Image API）：用的地方别一直等
  function G.opticFailed(key) return failed[key] == true end

  -- 有没有现成的（导入的或已经生成好的），不复制
  function G.opticReady(key)
    return META[key] ~= nil and (imported(key) ~= nil or gen[key] ~= nil)
  end

  -- 原模型没贴图的瞄准镜（两具 ACOG：一片平涂的灰，看着像塑料——用户 11-21：镜身、目镜圈太假）：按真东西的料子上 Roblox 自带材质——
  --   镜身阳极氧化的铝（金属：细纹理、高光），目镜罩橡胶（哑光），镜片玻璃，分划发光；没写的块照旧
  local SURF = {
    acog = { default = "Metal", Eyepiece = "Rubber", GlassIn = "Glass", Fiber = "SmoothPlastic", FiberIn = "SmoothPlastic",
      FiberCover = "SmoothPlastic", FiberCoverIn = "SmoothPlastic", ReticleIn = "Neon" },
    opt_acog6 = { default = "Metal", Eyepiece = "Rubber", C9ab = "Glass", C9abIn = "Glass", Cb22 = "SmoothPlastic", Cf00In = "Neon" },
  }
  local function surface(key, name, p)
    local sf = SURF[key]
    local m = sf and (sf[name] or sf.default)
    if m then pcall(function() p.Material = Enum.Material[m] end) end
  end

  function G.opticParts(key)
    if not META[key] or failed[key] then return nil end
    local list = imported(key) or gen[key]
    if not list then
      build(key)
      return nil
    end
    local out = {}
    for _, x in ipairs(list) do
      local ok, p = pcall(function() return x.src:Clone() end)
      if ok and p then
        quiet(p)
        if x.src:IsDescendantOf(RS) then Tint.fix(p, x.src) end
        surface(key, x.name, p)
        table.insert(out, { name = x.name, part = p, c = x.c, cf = x.cf })
      end
    end
    if #out == 0 then
      -- 有模型却一块也复制不出来（导入的零件不能复制、现生成的网格不让复制）：记成失败，用零件拼的。
      --   原来 opticReady 一直说「好了」、这里一直给 nil，第一人称每一帧都重建一遍视图模型——切到火箭筒就卡住（用户：第一人称用枪切火箭炮会卡住）
      failed[key] = true
      warn("[全面大战场] 装备模型 " .. key .. " 复制不出来，用零件拼的代替")
      return nil
    end
    return out
  end

  -- 出生以后：背包里的装备有真模型的，后台一件一件先生成好（第一次切过去不用现生成，不卡那一下）
  local me = game:GetService("Players").LocalPlayer
  local function prewarm(char)
    task.delay(3, function()
      local bp = me:FindFirstChildOfClass("Backpack")
      local keys = {}
      for _, holder in ipairs({ bp, char }) do
        if holder then
          for _, t in ipairs(holder:GetChildren()) do
            if t:IsA("Tool") then
              for _, a in ipairs({ "Gear", "GearMount" }) do
                local k = t:GetAttribute(a)
                if type(k) == "string" and META[k] then keys[k] = true end
              end
            end
          end
        end
      end
      for k in pairs(keys) do
        if not imported(k) then build(k) end
        task.wait(0.5)
      end
    end)
  end
  me.CharacterAdded:Connect(prewarm)
  if me.Character then prewarm(me.Character) end

  -- 开局后台先生成第一人称已经在用的（狙击镜、望远镜；导入了就不用）；别的件（狙击枪、火箭筒等，还没接进第一人称）用到时才生成，免得手机内存白占
  task.delay(4, function()
    for _, key in ipairs({ "acog", "atacr", "binoc" }) do   -- 步枪的 ACOG 人人都用：最先生成
      if META[key] and not imported(key) then build(key) end
      task.wait(1)
    end
  end)
end

return Optics
