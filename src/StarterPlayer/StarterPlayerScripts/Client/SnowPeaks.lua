-- 全面大战场（客户端）——雪山地图谷外的山体：用户 11-26 晚「坦克交战区外你就用这几个拿去拼」「让这个地图望不到头」
--   6 个 Sketchfab 山体模型（CC-BY，models/snow/<键>.glb：Studio「导入 3D」导入后 Imports.lua 收进 ReplicatedStorage.Imported.Peaks.<键>）
--   按摆法表（ReplicatedStorage.SnowPeaks：tools/snow/layout.py 生成，一百七十来座，外圈铺到四万多格）在本机克隆、摆好：
--   · 只在本机有（不走服务器、不受串流的半径限制，四万格外的山也看得见；服务器那边的高度按 MapSnow 的山体高度图算，飞机撞山照样算）
--   · 不挡人、不挡射线（体素地形在下面四格托着：谷边山脚的碰撞是体素的）
--   · 离镜头近的先摆、每帧最多摆 PER_FRAME 块（几千块一下摆完会卡一下）；手摆的内圈投影子，外圈自动铺的不投（远处看不出，省显卡）
--   · 换到别的地图全部收掉
--   G.snowPeaksStats() → { want, placed, missing }（测试、性能面板看）
local RS = game:GetService("ReplicatedStorage")
-- Studio 导入 GLB 时每块网格在自己的坐标里绕 Y 转了半圈（ImportTurn.lua）：摆的时候右乘 TURN 转回来，同载具、楼房
local TURN = CFrame.Angles(0, math.pi, 0)
pcall(function() TURN = require(RS:WaitForChild("ImportTurn", 5)).TURN end)

local SnowPeaks = {}

local PER_FRAME = 120

function SnowPeaks.init(G)
  local Map = G.Map
  local folder = nil
  local queue, qi = {}, 1
  local placed, missing, want = 0, {}, 0
  local warned = false
  local meta = nil

  local function clear()
    if folder then folder:Destroy() end
    folder = nil
    table.clear(queue)
    qi, placed, want = 1, 0, 0
    table.clear(missing)
  end

  local function importedOf(key)
    local imp = RS:FindFirstChild("Imported")
    local pk = imp and imp:FindFirstChild("Peaks")
    return pk and pk:FindFirstChild(key)
  end

  local function build()
    clear()
    if Map.NAME ~= "snow" or not Map.PEAKS or #Map.PEAKS == 0 then return end
    if not meta then
      local ok, m = pcall(function() return require(RS:WaitForChild("SnowPeaksMeta", 10)) end)
      meta = ok and m or nil
    end
    if not meta then return end
    folder = Instance.new("Folder")
    folder.Name = "SnowPeaks"
    folder.Parent = workspace
    -- 每一块排进队：离地图中心近的先（进服时镜头多半在两边基地 / 谷里）
    for _, I in ipairs(Map.PEAKS) do
      local M = meta[I.key]
      if M then
        for _, ch in ipairs(M.chunks) do
          table.insert(queue, { I = I, ch = ch, d = I.x * I.x + I.z * I.z })
        end
      end
    end
    table.sort(queue, function(a, b) return a.d < b.d end)
    want = #queue
  end

  -- 摆一块：模型坐标（烘焙：x、z 居中、最低点 y = 0）里的块中心 → 世界（同 MapSnow 的 peakH：模型 → 世界 x = (lx cos − lz sin)·k、z = (lx sin + lz cos)·k）
  local function place(item)
    local I, ch = item.I, item.ch
    local src = importedOf(I.key)
    local part = src and src:FindFirstChild("P_" .. I.key .. "__" .. ch[1])
    if not part then
      missing[I.key] = true
      return false
    end
    local k = I.k
    local lx, ly, lz = ch[2], ch[3], ch[4]
    local dx = (lx * I.c - lz * I.s) * k
    local dz = (lx * I.s + lz * I.c) * k
    local p = part:Clone()
    p.Anchored = true
    p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
    p.Locked = true
    p.CastShadow = not I.fill
    local ky = I.ky or k   -- 竖着另外放大（山脊拉高、底下的台地埋进雪原）
    p.Size = Vector3.new(ch[5] * k, ch[6] * ky, ch[7] * k)
    -- 转角：layout 里的 yaw 是从上往下看顺时针；Roblox 的 Y 轴转角正的是逆时针 → 取负
    p.CFrame = CFrame.new(I.x + dx, I.y + ly * ky, I.z + dz) * CFrame.Angles(0, -math.atan2(I.s, I.c), 0) * TURN
    p.Parent = folder
    return true
  end

  local function step()
    if not folder or qi > #queue then return end
    local n = 0
    while qi <= #queue and n < PER_FRAME do
      local item = queue[qi]
      qi += 1
      if place(item) then placed += 1 end
      n += 1
    end
    if qi > #queue and next(missing) and not warned then
      warned = true
      local ks = {}
      for k in pairs(missing) do table.insert(ks, k) end
      table.sort(ks)
      warn("[全面大战场] 雪山的山体模型还没导入（" .. table.concat(ks, "、") .. "）：Studio「导入 3D」导入 models/snow/ 下对应的 .glb（每个一次）")
    end
  end

  G.frameConn("snowpeaks", step)
  G.onMap(function() build() end)
  build()
  G.snowPeaksStats = function()
    local m = {}
    for k in pairs(missing) do table.insert(m, k) end
    return { want = want, placed = placed, missing = m, queued = #queue - qi + 1 }
  end
end

return SnowPeaks
