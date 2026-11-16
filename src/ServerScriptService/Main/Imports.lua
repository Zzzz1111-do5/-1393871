-- Roblox全面大战场——收导入的模型：Studio 里「导入 3D」导入 models/veh/<模型键>.glb 以后，MeshPart 叫 V_<模型键>__<部件>（Body_1、Turret_2、Gun_1、W01……），
--   不管导进来放在 Workspace、ReplicatedStorage 还是 ServerStorage，开服时按名字收进 ReplicatedStorage.Imported.Veh.<模型键>，
--   客户端（VehModels.lua）拼车时看这里有没有，有就换上真模型；导入时自带的空 Model / 文件夹顺手删掉
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

  local veh = folder(folder(RS, "Imported"), "Veh")
  local optics = folder(folder(RS, "Imported"), "Optics")   -- 瞄准镜、望远镜（models/optics/<键>.glb，块叫 O_<键>__<块名>）
  local n, keys = 0, {}
  local emptied = {}
  for _, root in ipairs({ workspace, RS, ServerStorage }) do
    for _, d in ipairs(root:GetDescendants()) do
      if d:IsA("BasePart") and not d:IsDescendantOf(veh) and not d:IsDescendantOf(optics) then
        local key, part = string.match(d.Name, "^V_(%w+)__([%w_]+)$")
        local okey = string.match(d.Name, "^O_(%w+)__[%w_]+$")
        if okey then
          local parent = d.Parent
          d.Anchored = true
          d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
          d.Parent = folder(optics, okey)
          if parent and parent ~= workspace and parent ~= RS and parent ~= ServerStorage then emptied[parent] = true end
        elseif key then
          local parent = d.Parent
          d.Anchored = true
          d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
          d.Parent = folder(veh, key)
          n += 1
          if not keys[key] then keys[key] = true end
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
  local list = {}
  for k in pairs(keys) do table.insert(list, k) end
  table.sort(list)
  G.importedVeh = list
  if n > 0 then print("[全面大战场] 用上了导入的装备模型：" .. table.concat(list, "、") .. "（" .. n .. " 块）") end
end

return Imports
