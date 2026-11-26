-- 全面大战场（服务器）——远景替身的清单（用户 11-26「这个地图 streaming 太出戏了……很多游戏用了这种优化技术但还是很丝滑、能看到远方的场景」）
--   开着流式加载（Workspace.StreamingEnabled）时客户端只收到身边一片的房子，远处的楼是一块块冒出来的。
--   Roblox 自带的远景（Model.LevelOfDetail = StreamingMesh / SLIM）只给发布时就摆在地点文件里的模型做，我们的楼都是开服时程序摆的，用不上。
--   做法：开服摆完地图以后，把每栋整栋流进流出（Atomic）的楼、每块很大的地面零件（路、跑道）记成几块简化的「替身」：
--     导入的写实楼（ReplicatedStorage.Imported.Bld 里有原网格）记网格块的名字和位置——客户端照原网格摆；其余记最大的几块方块（位置、转角、大小、颜色、材质）
--   清单写进 ReplicatedStorage.FarLod（几段 StringValue，每段不超过 9 万字），楼本身打标签 FarLod、属性 FarId——
--   客户端（Client/FarLod.lua）楼在身边（流进来了）就藏起替身，流出去 / 还没来就画替身；楼被炸没了（Destroying）记进 Gone，客户端把那个替身去掉
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")

local FarLod = {}

function FarLod.init(G)
  local MAXB = 8          -- 每栋最多几块方块
  local BIGPART = 160     -- 不在整栋模型里的零件：最长边超过这么多（路、跑道、大块地面）才记
  local CHUNK = 90000
  local MATS = { Enum.Material.SmoothPlastic, Enum.Material.Concrete, Enum.Material.Brick, Enum.Material.Glass, Enum.Material.Metal,
    Enum.Material.Asphalt, Enum.Material.Slate, Enum.Material.Wood, Enum.Material.WoodPlanks, Enum.Material.Ground, Enum.Material.Sand,
    Enum.Material.CorrodedMetal, Enum.Material.DiamondPlate, Enum.Material.Cobblestone, Enum.Material.Pavement, Enum.Material.Plastic }
  local MIDX = {}
  for i, m in ipairs(MATS) do MIDX[m] = i end
  local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
  local function hex(c) return string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end
  local function cfStr(cf, size)
    local p = cf.Position
    local rx, ry, rz = cf:ToEulerAnglesXYZ()
    return table.concat({ r1(p.X), r1(p.Y), r1(p.Z), r1(math.deg(rx)), r1(math.deg(ry)), r1(math.deg(rz)), r1(size.X), r1(size.Y), r1(size.Z) }, ",")
  end
  local function visible(p) return p.Transparency < 0.95 and p.Name ~= "Collision" and p.Size.Magnitude > 2 end

  local gone = {}
  local holder, goneV = nil, nil
  local function markGone(id)
    if gone[id] then return end
    gone[id] = true
    if goneV then goneV.Value = goneV.Value .. tostring(id) .. "," end
  end

  -- 一栋楼的替身：导入的网格块全记（客户端照原网格摆），其余按体积挑最大的几块方块
  local function pieces(m)
    local key = m:GetAttribute("Bld")
    local imp = RS:FindFirstChild("Imported")
    local src = key and imp and imp:FindFirstChild("Bld") and imp.Bld:FindFirstChild(key)
    local out, boxes = {}, {}
    for _, p in ipairs(m:GetDescendants()) do
      if p:IsA("BasePart") and visible(p) then
        if src and p:IsA("MeshPart") and src:FindFirstChild(p.Name) then
          if #out < 40 then table.insert(out, "m," .. key .. "," .. p.Name .. "," .. cfStr(p.CFrame, p.Size) .. "," .. hex(p.Color)) end
        elseif p.ClassName == "Part" or p.ClassName == "WedgePart" or p:IsA("MeshPart") then
          table.insert(boxes, p)
        end
      end
    end
    table.sort(boxes, function(a, b) return a.Size.X * a.Size.Y * a.Size.Z > b.Size.X * b.Size.Y * b.Size.Z end)
    local v0 = boxes[1] and (boxes[1].Size.X * boxes[1].Size.Y * boxes[1].Size.Z) or 0
    for i = 1, math.min(MAXB, #boxes) do
      local p = boxes[i]
      if p.Size.X * p.Size.Y * p.Size.Z < v0 * 0.02 then break end
      local w = (p.ClassName == "WedgePart") and "w" or "b"
      table.insert(out, w .. "," .. cfStr(p.CFrame, p.Size) .. "," .. hex(p.Color) .. "," .. tostring(MIDX[p.Material] or 1))
    end
    return out
  end

  function G.farLodPublish()
    local map = workspace:FindFirstChild("Map")
    if not map then return end
    local lines, id = {}, 0
    local function add(inst, ps)
      if #ps == 0 then return end
      id += 1
      inst:SetAttribute("FarId", id)
      CS:AddTag(inst, "FarLod")
      table.insert(lines, tostring(id) .. ";" .. table.concat(ps, ";"))
      local my = id
      inst.Destroying:Connect(function() markGone(my) end)
      inst.AncestryChanged:Connect(function(_, par) if par == nil then markGone(my) end end)
    end
    local nModel, nPart = 0, 0
    local function walk(f)
      for _, c in ipairs(f:GetChildren()) do
        if c:IsA("Model") then
          local mode = Enum.ModelStreamingMode.Default
          pcall(function() mode = c.ModelStreamingMode end)
          if mode == Enum.ModelStreamingMode.Atomic then
            add(c, pieces(c))
            nModel += 1
          elseif mode ~= Enum.ModelStreamingMode.Persistent and mode ~= Enum.ModelStreamingMode.PersistentPerPlayer then
            walk(c)
          end
        elseif c:IsA("BasePart") then
          if visible(c) and math.max(c.Size.X, c.Size.Y, c.Size.Z) >= BIGPART and c.ClassName == "Part" then
            add(c, { "b," .. cfStr(c.CFrame, c.Size) .. "," .. hex(c.Color) .. "," .. tostring(MIDX[c.Material] or 1) })
            nPart += 1
          end
        elseif c:IsA("Folder") then
          walk(c)
        end
      end
    end
    walk(map)
    holder = RS:FindFirstChild("FarLod") or Instance.new("Folder")
    holder.Name = "FarLod"
    for _, c in ipairs(holder:GetChildren()) do c:Destroy() end
    goneV = Instance.new("StringValue")
    goneV.Name = "Gone"
    goneV.Value = ""
    goneV.Parent = holder
    -- 按整行分段（不从一个字的中间切开）
    local n, buf, len, total = 0, {}, 0, 0
    local function flush()
      if #buf == 0 then return end
      n += 1
      local sv = Instance.new("StringValue")
      sv.Name = "M" .. n
      sv.Value = table.concat(buf, "\n")
      sv.Parent = holder
      buf, len = {}, 0
    end
    for _, l in ipairs(lines) do
      if len + #l + 1 > CHUNK then flush() end
      table.insert(buf, l)
      len += #l + 1
      total += #l + 1
    end
    flush()
    local all = { n = total }
    holder:SetAttribute("N", n)
    holder:SetAttribute("Count", id)
    holder.Parent = RS
    G.farLodInfo = { models = nModel, parts = nPart, bytes = all.n, chunks = n }
    print(string.format("[全面大战场] 远景替身：%d 栋楼、%d 块大地面，清单 %d 字（%d 段）", nModel, nPart, all.n, n))
  end
end

return FarLod
