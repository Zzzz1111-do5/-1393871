-- 全面大战场（客户端）——流式加载（Workspace.StreamingEnabled）的配套：用户 11-24 晚「streaming 优化」「各种 3A 游戏的那种优化」
--   地点文件里开了 streaming（tools/build_rbxlx.py、tools/build.luau 写的 Workspace 属性）以后，客户端只有身边一片（StreamingTargetRadius 以内）的
--   地图零件和地形；远处的地形照样画得出来（低细节），可是客户端的射线打不到它——激光测距、瞄准点、标点、舰炮的落点都会打空。
--   这里给一个统一的射线：先照常打 workspace:Raycast，打空了、又开着 streaming、射线朝下：按 Map.rayGround（地形本来就是按 Map.height 写的）找落点，
--   返回一个跟 RaycastResult 一样用的表（Position / Normal / Distance / Instance = Terrain / Material）
--   一直要在的东西（实体代理 Ents、玩家角色、舰队、据点）服务器设成 Persistent（Ents.lua、World.lua、Round.lua），不受这里管
--   G.streaming：这局开没开（地点文件决定，脚本改不了）；G.rayFar(起点, 向量, RaycastParams[, 朝上也算])；G.terrainBlocks(甲, 乙) 远处的地形挡不挡视线；
--   G.streamStats() 性能面板看
local RS = game:GetService("ReplicatedStorage")

local Stream = {}

function Stream.init(G)
  local Map = G.Map or require(RS:WaitForChild("Map"))
  local on = false
  pcall(function() on = workspace.StreamingEnabled == true end)
  G.streaming = on
  local fallbacks = 0   -- 打空了按地形算出来的次数（性能面板、测试看）

  -- 地形的法线：高度的梯度
  local function normalAt(x, z)
    local e = 2
    local hx = (Map.height(x + e, z)) - (Map.height(x - e, z))
    local hz = (Map.height(x, z + e)) - (Map.height(x, z - e))
    return Vector3.new(-hx, 2 * e, -hz).Unit
  end

  --   any：朝上、水平的也按地形算（激光测距按一下打一次：往上坡打要测得到）；每帧都打的瞄准射线不给——朝天打空了还一步步走，白费时间
  function G.rayFar(o, v, params, any)
    local res = workspace:Raycast(o, v, params)
    if res or not G.streaming or (v.Y >= 0 and not any) then return res end
    local p, dist = Map.rayGround(o, v)
    if not p then return nil end
    fallbacks += 1
    local okM, mat = pcall(Map.material, p.X, p.Z, p.Y, 0)
    return { Position = p, Normal = normalAt(p.X, p.Z), Distance = dist, Instance = workspace.Terrain,
      Material = (okM and typeof(mat) == "EnumItem") and mat or Enum.Material.Ground, far = true }
  end

  -- 两点之间的视线被不被远处的地形挡住（普通射线打空以后再问这个）：没加载的山也算——飞机 HUD 挑一万多格外的敌机（TankHud.lua）。
  --   近处（3000 格以内）的地形一定加载着，普通射线已经算过了；只看远的，免得按公式算的地形和真地形差一两格、贴地的视线被误判挡住
  function G.terrainBlocks(from, to)
    if not G.streaming then return false end
    local v = to - from
    local L = v.Magnitude
    if L < 3000 then return false end
    local _, dist = Map.rayGround(from, v, math.clamp(L / 120, 8, 80))
    return dist ~= nil and dist < L - 6
  end

  function G.streamStats()
    local map = workspace:FindFirstChild("Map")
    local n = 0
    if map then n = #map:GetDescendants() end
    return { on = G.streaming, mapInst = n, fallbacks = fallbacks }
  end
end

return Stream
