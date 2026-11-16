-- Roblox全面大战场（客户端）——瞄准镜、望远镜的真模型（Sketchfab 上的原模型，几何和贴图原样）：给第一人称（FPSView）用
--   有导入的（Studio 里导入 models/optics/<键>.glb，Imports.lua 收进 ReplicatedStorage.Imported.Optics.<键>，带原来的 PBR 贴图）就用它；
--   没有就用 OpticMesh/<键> 里嵌的网格和底色贴图，开局在后台用 EditableMesh / EditableImage 生成（要在游戏设置 → 安全里打开 Mesh / Image API）；
--   两样都没有时 G.opticParts 返回 nil，FPSView 照旧用零件拼的
--   G.opticParts(键) → { { name 块名, part 复制出来的 MeshPart, c 块中心（器材坐标） }, … }；G.opticMeta = OpticsMeta（目镜、物镜的位置和半径）
local RS = game:GetService("ReplicatedStorage")

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
    local list = {}
    for name, info in pairs(META[key].parts) do
      local src = f:FindFirstChild("O_" .. key .. "__" .. name)
      if src and src:IsA("BasePart") then table.insert(list, { name = name, src = src, c = V(info.c[1], info.c[2], info.c[3]) }) end
    end
    return (#list > 0) and list or nil
  end

  -- 嵌在游戏里的：后台生成一次，之后复制
  local gen, busy, failed = {}, {}, {}
  local function build(key)
    if gen[key] or busy[key] or failed[key] then return end
    busy[key] = true
    task.spawn(function()
      local ok, err = pcall(function()
        local D = require(RS:WaitForChild("OpticMesh", 5):WaitForChild(key, 5))
        local AS = game:GetService("AssetService")
        local list = {}
        for name, d in pairs(D.parts) do
          local pos, nrm, uv, idx = unb64(d.pos), unb64(d.nrm), unb64(d.uv), unb64(d.idx)
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
            if i % 4000 == 3999 then task.wait() end
          end
          for t = 0, d.t - 1 do
            local a, b2, c = string.unpack("<HHH", idx, t * 6 + 1)
            local f = em:AddTriangle(vid[a + 1], vid[b2 + 1], vid[c + 1])
            em:SetFaceNormals(f, { nid[a + 1], nid[b2 + 1], nid[c + 1] })
            em:SetFaceUVs(f, { uid[a + 1], uid[b2 + 1], uid[c + 1] })
            if t % 4000 == 3999 then task.wait() end
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
          table.insert(list, { name = name, src = mp, c = info and V(info.c[1], info.c[2], info.c[3]) or V() })
          task.wait()
        end
        gen[key] = list
      end)
      busy[key] = nil
      if not ok then
        failed[key] = true
        warn("[全面大战场] 瞄准镜模型 " .. key .. " 生成不了（用零件拼的代替；在 Studio 的游戏设置 → 安全里打开 Mesh / Image API，或者导入 models/optics/" .. key .. ".glb）：" .. tostring(err))
      end
    end)
  end

  -- 有没有现成的（导入的或已经生成好的），不复制
  function G.opticReady(key)
    return META[key] ~= nil and (imported(key) ~= nil or gen[key] ~= nil)
  end

  function G.opticParts(key)
    if not META[key] then return nil end
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
        table.insert(out, { name = x.name, part = p, c = x.c })
      end
    end
    return (#out > 0) and out or nil
  end

  -- 开局后台先生成（导入了就不用）
  task.delay(4, function()
    for key in pairs(META) do
      if not imported(key) then build(key) end
      task.wait(1)
    end
  end)
end

return Optics
