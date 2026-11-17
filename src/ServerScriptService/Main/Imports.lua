-- Roblox全面大战场——收导入的模型：Studio 里「导入 3D」导入 models/veh/<模型键>.glb（地面载具）、models/air/<模型键>.glb（飞机直升机）、
--   models/ship/<型号>.glb（舰艇）、models/optics/<键>.glb（瞄准镜、手持装备）、models/scenery/scenery.glb（花草树木，一个文件全有）以后，
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
  -- V 地面载具、A 飞机直升机、S 舰艇、O 瞄准镜望远镜和手持装备（models/optics/<键>.glb，块叫 O_<键>__<块名>）
  local dest = { V = folder(imported, "Veh"), A = folder(imported, "Air"), S = folder(imported, "Ship"), O = folder(imported, "Optics"), N = folder(imported, "Scenery") }
  local n, keys, airKeys, shipKeys = 0, {}, {}, {}
  local emptied = {}
  for _, root in ipairs({ workspace, RS, ServerStorage }) do
    for _, d in ipairs(root:GetDescendants()) do
      if d:IsA("BasePart") and not d:IsDescendantOf(imported) then
        local kind, key = string.match(d.Name, "^([VASON])_([%w_]-)__[%w_]+$")
        if not kind and string.match(d.Name, "^FPS_M4_%w+$") then   -- 第一人称的 M4（models/fps_m4.glb）：收进 Imported.FPS_M4（FPSView 在那里找）
          local parent = d.Parent
          d.Anchored = true
          d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
          d.Parent = folder(imported, "FPS_M4")
          if parent and parent ~= workspace and parent ~= RS and parent ~= ServerStorage then emptied[parent] = true end
        elseif kind == "O" or kind == "N" then   -- 瞄准镜、花草树木：只收好，不算进装备模型（花草树木的键里有下划线：fir1_m、grass_s）
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
  if n > 0 then
    print("[全面大战场] 用上了导入的装备模型：" .. table.concat(G.importedVeh, "、") .. ((#G.importedAir > 0) and ("；飞机直升机：" .. table.concat(G.importedAir, "、")) or "")
      .. ((#G.importedShip > 0) and ("；舰艇：" .. table.concat(G.importedShip, "、")) or "") .. "（" .. n .. " 块）")
  end
end

return Imports
