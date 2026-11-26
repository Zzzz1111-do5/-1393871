-- 全面大战场（客户端）——远景替身（用户 11-26「streaming 太出戏了……很多游戏用了这种优化技术但还是很丝滑、能看到远方的场景」）
--   服务器（Main/FarLod.lua）开服摆完地图后发一份清单：每栋整栋流进流出的楼、每块大地面（路、跑道）几块简化的替身。
--   这里照清单在本机摆替身（只有本机有、不发服务器）：导入的写实楼照原网格摆（ReplicatedStorage.Imported.Bld 里的网格块，远处 Roblox 自己降面），其余是方块；
--   不挡人、不挡射线（CanCollide / CanQuery / CanTouch 都关）、不投影子（远处看不出，省显卡）。
--   真楼流进来了（标签 FarLod 的东西到了本机：CollectionService 的 InstanceAdded）就藏起它的替身，流出去（InstanceRemoved）再摆回来——
--   近处永远是真楼，远处永远看得到轮廓，不会一块块冒出来；楼被炸没了服务器记在 Gone 里，替身跟着去掉
--   G.farLodStats() → { total, shown, hidden, gone }（测试、性能面板看）
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")

local FarLod = {}

function FarLod.init(G)
  local MATS = { Enum.Material.SmoothPlastic, Enum.Material.Concrete, Enum.Material.Brick, Enum.Material.Glass, Enum.Material.Metal,
    Enum.Material.Asphalt, Enum.Material.Slate, Enum.Material.Wood, Enum.Material.WoodPlanks, Enum.Material.Ground, Enum.Material.Sand,
    Enum.Material.CorrodedMetal, Enum.Material.DiamondPlate, Enum.Material.Cobblestone, Enum.Material.Pavement, Enum.Material.Plastic }
  local folder = Instance.new("Folder")
  folder.Name = "FarLod"
  local proxies = {}   -- FarId → { m = 替身模型, real = 真楼在不在本机, gone = 炸没了 }
  local nGone = 0
  local function rad(v) return math.rad(tonumber(v) or 0) end
  local function split(s, sep)   -- 同 string.split（按字面的分隔符切；模拟器的 Lua 没有 string.split）
    local out, i = {}, 1
    while true do
      local j = string.find(s, sep, i, true)
      if not j then table.insert(out, string.sub(s, i)) break end
      table.insert(out, string.sub(s, i, j - 1))
      i = j + 1
    end
    return out
  end
  local function col(h)
    h = tostring(h or "")
    if #h ~= 6 then return Color3.fromRGB(150, 150, 150) end
    return Color3.fromRGB(tonumber(h:sub(1, 2), 16) or 150, tonumber(h:sub(3, 4), 16) or 150, tonumber(h:sub(5, 6), 16) or 150)
  end
  local function quiet(p)
    p.Anchored = true
    p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
    p.CastShadow = false
    p.Massless = true
    p.Locked = true
    for _, d in ipairs(p:GetDescendants()) do   -- 网格块上带的灯、声音、粒子：远景不要
      if d:IsA("Light") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
    end
  end
  local function place(f, at)   -- 位置 x y z、转角 rx ry rz（度）、大小 sx sy sz：清单字段从第 at 个起
    local cf = CFrame.new(tonumber(f[at]) or 0, tonumber(f[at + 1]) or 0, tonumber(f[at + 2]) or 0)
      * CFrame.fromEulerAnglesXYZ(rad(f[at + 3]), rad(f[at + 4]), rad(f[at + 5]))
    local sz = Vector3.new(math.max(0.2, tonumber(f[at + 6]) or 1), math.max(0.2, tonumber(f[at + 7]) or 1), math.max(0.2, tonumber(f[at + 8]) or 1))
    return cf, sz
  end
  local function build(line)
    local items = split(line, ";")
    local id = tonumber(items[1])
    if not id then return end
    local m = Instance.new("Model")
    m.Name = "Far_" .. id
    local imp = RS:FindFirstChild("Imported")
    local bld = imp and imp:FindFirstChild("Bld")
    for i = 2, #items do
      local f = split(items[i], ",")
      local k = f[1]
      local p = nil
      if k == "m" then
        local src = bld and bld:FindFirstChild(f[2])
        local s0 = src and src:FindFirstChild(f[3])
        if s0 and s0:IsA("BasePart") then
          p = s0:Clone()
          local cf, sz = place(f, 4)
          p.Size, p.CFrame = sz, cf
          local okT, tid = pcall(function() return p.TextureID end)
          if not p:FindFirstChildOfClass("SurfaceAppearance") and (not okT or (tid or "") == "") then p.Color = col(f[13]) end
        end
      elseif k == "b" or k == "w" then
        p = Instance.new((k == "w") and "WedgePart" or "Part")
        local cf, sz = place(f, 2)
        p.Size, p.CFrame = sz, cf
        p.Color = col(f[11])
        p.Material = MATS[tonumber(f[12]) or 1] or Enum.Material.SmoothPlastic
        p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
      end
      if p then
        quiet(p)
        p.Parent = m
      end
    end
    proxies[id] = { m = m, real = false, gone = false }
  end
  local function show(id)
    local e = proxies[id]
    if not e then return end
    local want = (not e.real) and not e.gone
    local par = want and folder or nil
    if e.m.Parent ~= par then e.m.Parent = par end
  end
  local function realIn(inst)
    local id = inst:GetAttribute("FarId")
    local e = id and proxies[id]
    if e then e.real = true show(id) end
  end
  local function realOut(inst)
    local id = inst:GetAttribute("FarId")
    local e = id and proxies[id]
    if e then e.real = false show(id) end
  end
  local function readGone(v)
    for s in string.gmatch(v.Value or "", "(%d+),") do
      local id = tonumber(s)
      local e = id and proxies[id]
      if e and not e.gone then
        e.gone = true
        nGone += 1
        show(id)
      end
    end
  end

  local loaded, ready = false, false   -- loaded：清单收全了开始摆；ready：摆完了
  local function load(holder)
    if loaded then return end
    local n = holder:GetAttribute("N")
    if type(n) ~= "number" then return end
    local parts = {}
    for i = 1, n do
      local sv = holder:FindFirstChild("M" .. i)
      if not sv then return end   -- 还没传全：等 ChildAdded
      parts[i] = sv.Value
    end
    loaded = true
    local all = table.concat(parts, "\n")
    local k = 0
    for line in string.gmatch(all, "[^\n]+") do
      build(line)
      k += 1
      if k % 60 == 0 then task.wait() end   -- 分几帧摆：进服那一下不卡
    end
    for _, inst in ipairs(CS:GetTagged("FarLod")) do realIn(inst) end
    for id in pairs(proxies) do show(id) end
    folder.Parent = workspace
    ready = true
    local gv = holder:FindFirstChild("Gone")
    if gv then
      readGone(gv)
      gv:GetPropertyChangedSignal("Value"):Connect(function() readGone(gv) end)
    end
  end
  CS:GetInstanceAddedSignal("FarLod"):Connect(realIn)
  CS:GetInstanceRemovedSignal("FarLod"):Connect(realOut)
  task.spawn(function()
    local holder = RS:WaitForChild("FarLod", 600)
    if not holder then return end
    holder.ChildAdded:Connect(function() task.defer(load, holder) end)
    holder:GetAttributeChangedSignal("N"):Connect(function() task.defer(load, holder) end)
    load(holder)
  end)

  function G.farLodStats()
    local t, s, h = 0, 0, 0
    for _, e in pairs(proxies) do
      t += 1
      if e.m.Parent then s += 1 elseif not e.gone then h += 1 end
    end
    return { total = t, shown = s, hidden = h, gone = nGone, loaded = ready }
  end
  G.farLodProxy = function(id) local e = proxies[id] return e and e.m end   -- 测试用
end

return FarLod
