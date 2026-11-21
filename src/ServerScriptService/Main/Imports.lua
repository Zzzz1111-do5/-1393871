-- Roblox全面大战场——收导入的模型：Studio 里「导入 3D」导入 models/veh/<模型键>.glb（地面载具）、models/air/<模型键>.glb（飞机直升机）、
--   models/ship/<型号>.glb（舰艇）、models/optics/<键>.glb（瞄准镜、手持装备）、models/scenery/scenery.glb（花草树木，一个文件全有）、
--   models/bld/buildings.glb（地图建筑：民房、水泥楼、机库、塔台、营房、库房……一个文件全有，块叫 B_<键>__Body_<号>，收进 Imported.Bld）以后，
--   MeshPart 叫 V_<模型键>__<块>（Body_1、Turret_2、Gun_1、W01_1……）/ N_<键>__<块>（Bark、Leaves、Body：地图上的树、灌木、石头、草丛、花丛）/
--   A_<模型键>__<块>（Body_1、Gear_1、Rotor_1……）/ S_<型号>__<块>（Hull_1、T1_1……）/ O_<键>__<块>，不管导进来放在 Workspace、ReplicatedStorage 还是 ServerStorage，
--   开服时按名字收进 ReplicatedStorage.Imported.Veh / Air / Ship / Optics.<模型键>（第一人称的 M4，models/fps_m4.glb 的 FPS_M4_* 收进 Imported.FPS_M4），
--   导入一次存成 models/imported/*.rbxm 的话，tools/build.luau 生成地图文件时把它放进 ServerStorage.ImportedModels，以后的版本都带着；
--   客户端（VehModels.lua、AirModels.lua）拼的时候看这里有没有，有就换上原模型；导入时自带的空 Model / 文件夹顺手删掉
local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Imports = {}

function Imports.init(G)
  local function folder(parent, name)
    local f = parent:FindFirstChild(name)
    if not f then
      f = Instance.new("Folder")
      f.Name = name
      f.Parent = parent
    end
    return f
  end

  local imported = folder(RS, "Imported")
  -- V 地面载具、A 飞机直升机、S 舰艇、O 瞄准镜望远镜和手持装备（models/optics/<键>.glb，块叫 O_<键>__<块名>）、
  --   W 机载导弹炸弹（models/wpn/missiles.glb，块叫 W_<型号>__Body_1；WeaponModels 有就用它）
  local dest = { V = folder(imported, "Veh"), A = folder(imported, "Air"), S = folder(imported, "Ship"), O = folder(imported, "Optics"), N = folder(imported, "Scenery"),
    W = folder(imported, "Wpn"), B = folder(imported, "Bld") }
  local n, keys, airKeys, shipKeys = 0, {}, {}, {}
  local emptied = {}
  for _, root in ipairs({ workspace, RS, ServerStorage }) do
    for _, d in ipairs(root:GetDescendants()) do
      if d:IsA("BasePart") and not d:IsDescendantOf(imported) then
        local kind, key = string.match(d.Name, "^([VASONWB])_([%w_]-)__[%w_]+$")
        if not kind and string.match(d.Name, "^FPS_M4_%w+$") then   -- 第一人称的 M4（models/fps_m4.glb）：收进 Imported.FPS_M4（FPSView 在那里找）
          local parent = d.Parent
          d.Anchored = true
          d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
          d.Parent = folder(imported, "FPS_M4")
          if parent and parent ~= workspace and parent ~= RS and parent ~= ServerStorage then emptied[parent] = true end
        elseif kind == "O" or kind == "N" or kind == "W" or kind == "B" then   -- B：地图建筑（World.lua 开服时摆）   -- 瞄准镜、花草树木、导弹炸弹：只收好，不算进装备模型（花草树木的键里有下划线：fir1_m、grass_s）
          local parent = d.Parent
          d.Anchored = true
          d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
          d.Parent = folder(dest[kind], key)
          if parent and parent ~= workspace and parent ~= RS and parent ~= ServerStorage then emptied[parent] = true end
        elseif key then
          local parent = d.Parent
          d.Anchored = true
          d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
          d.Parent = folder(dest[kind], key)
          n += 1
          if kind == "V" then keys[key] = true elseif kind == "A" then airKeys[key] = true else shipKeys[key] = true end
          if parent and parent ~= workspace and parent ~= RS and parent ~= ServerStorage then emptied[parent] = true end
        end
      end
    end
  end
  -- 导入时外面包着的 Model（V_<键>、Vehicles）：里面空了就删
  for p in pairs(emptied) do
    local cur = p
    while cur and cur.Parent and cur ~= workspace and cur ~= RS and cur ~= ServerStorage and #cur:GetDescendants() == 0 do
      local up = cur.Parent
      cur:Destroy()
      cur = up
    end
  end
  local function sorted(t)
    local list = {}
    for k in pairs(t) do table.insert(list, k) end
    table.sort(list)
    return list
  end
  G.importedVeh, G.importedAir, G.importedShip = sorted(keys), sorted(airKeys), sorted(shipKeys)
  -- 每个模型的文件夹记下有几块（属性 N）：进服时几千块是陆续复制到客户端的，客户端等这些块都到了再用，
  --   不然先到的半架飞机 / 半辆车会一直缺块，或者一直当成「没导入」用零件拼的（用户：很多飞机找不到建模）
  for _, root in ipairs({ dest.V, dest.A, dest.S, dest.O, dest.N, imported:FindFirstChild("FPS_M4") }) do
    if root then
      if root.Name == "FPS_M4" then root:SetAttribute("N", #root:GetChildren())
      else for _, f in ipairs(root:GetChildren()) do if f:IsA("Folder") then f:SetAttribute("N", #f:GetChildren()) end end end
    end
  end
  if n > 0 then
    print("[全面大战场] 用上了导入的装备模型：" .. table.concat(G.importedVeh, "、") .. ((#G.importedAir > 0) and ("；飞机直升机：" .. table.concat(G.importedAir, "、")) or "")
      .. ((#G.importedShip > 0) and ("；舰艇：" .. table.concat(G.importedShip, "、")) or "") .. "（" .. n .. " 块）")
  end
  -- 飞机：每一型找不找得到原模型（照客户端 AirModels.importedFor 的顺序：新版 → 老版），没导入的、缺块的在输出窗口列出来，
  --   看得出该补导哪个文件（用户：很多飞机找不到建模）。缺的体积不到百分之三、块数不到四分之一的客户端照样用
  local okM, IA = pcall(function() return require(RS:WaitForChild("ImportedAir", 5)) end)
  local okD, AD = pcall(function() return require(RS:WaitForChild("AirDefs", 5)) end)
  if okM and okD and type(IA) == "table" and type(AD) == "table" and IA.m then
    local none, partial = {}, {}
    local function file(k) return (string.gsub(string.gsub(k, "~$", ""), "_v%d+$", "")) .. ".glb" end   -- 仓库里的文件名不带版本（j20.glb 里是 A_j20_v3__…）
    local ids = {}
    for id in pairs(AD.D or {}) do table.insert(ids, id) end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local keys = {}
      if IA.alias and IA.alias[id] then table.insert(keys, IA.alias[id]) end
      local old = IA.old and IA.old[id]
      if type(old) == "string" then table.insert(keys, old) elseif type(old) == "table" then for _, k in ipairs(old) do table.insert(keys, k) end end
      local best = nil
      for _, k in ipairs(keys) do
        k = string.gsub(k, "~$", "")
        local f, info = dest.A:FindFirstChild(k), IA.m[k]
        if f and info then
          local miss, total, mv, tv = 0, 0, 0, 0
          for name, p in pairs(info.parts) do
            local v = (p.s and p.s[1] * p.s[2] * p.s[3]) or 1
            total += 1
            tv += v
            if not f:FindFirstChild("A_" .. k .. "__" .. name) then miss += 1 mv += v end
          end
          local ok = miss == 0 or (miss <= total * 0.25 and mv <= tv * 0.03)
          if ok then best = nil break end
          best = best or string.format("%s（%s 缺 %d / %d 块）", id, file(k), miss, total)
        end
      end
      if best then table.insert(partial, best)
      else
        local any = false
        for _, k in ipairs(keys) do if dest.A:FindFirstChild((string.gsub(k, "~$", ""))) then any = true end end
        if not any and #keys > 0 then table.insert(none, id .. "（" .. file(keys[1]) .. "）") end
      end
    end
    if #none > 0 then print("[全面大战场] 这些飞机还没导入原模型，用零件拼的：" .. table.concat(none, "、") .. "——Studio「导入 3D」导入 models/air/ 下对应的文件") end
    if #partial > 0 then warn("[全面大战场] 这些飞机的原模型缺块太多，用零件拼的（重新导入一次）：" .. table.concat(partial, "、")) end
  end
end

return Imports
