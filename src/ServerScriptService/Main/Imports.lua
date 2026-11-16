-- Roblox全面大战场——收导入的模型：Studio 里「导入 3D」导入 models/veh/<模型键>.glb（地面载具）、models/air/<模型键>.glb（飞机直升机）以后，
--   MeshPart 叫 V_<模型键>__<块>（Body_1、Turret_2、Gun_1、W01_1……）/ A_<模型键>__<块>（Body_1、Gear_1、Rotor_1……），
--   不管导进来放在 Workspace、ReplicatedStorage 还是 ServerStorage，开服时按名字收进 ReplicatedStorage.Imported.Veh / Air.<模型键>，
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
  local dest = { V = folder(imported, "Veh"), A = folder(imported, "Air") }
  local n, keys, airKeys = 0, {}, {}
  local emptied = {}
  for _, root in ipairs({ workspace, RS, ServerStorage }) do
    for _, d in ipairs(root:GetDescendants()) do
      if d:IsA("BasePart") and not d:IsDescendantOf(imported) then
        local kind, key = string.match(d.Name, "^([VA])_(%w+)__[%w_]+$")
        if key then
          local parent = d.Parent
          d.Anchored = true
          d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
          d.Parent = folder(dest[kind], key)
          n += 1
          if kind == "V" then keys[key] = true else airKeys[key] = true end
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
  G.importedVeh, G.importedAir = sorted(keys), sorted(airKeys)
  if n > 0 then
    print("[全面大战场] 用上了导入的装备模型：" .. table.concat(G.importedVeh, "、") .. ((#G.importedAir > 0) and ("；飞机直升机：" .. table.concat(G.importedAir, "、")) or "")
      .. "（" .. n .. " 块）")
  end
end

return Imports
