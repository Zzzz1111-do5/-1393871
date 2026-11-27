-- 全面大战场（客户端）——雪山上空的体积云
--   用户 11-26 晚：「天上要有非常多的云 让飞机在天上飞也有立体感」——Sketchfab 上 Loïc Norgeot 的「Fluffy Cloud」（CC-BY 4.0）：
--   一团云是三个方向各 19 片叠起来的透明切片（tools/snow/clouds.py → models/snow/clouds.glb，导入后收进 Imported.Scenery.cloud 的
--   N_cloud__X / Y / Z 三块，大小 1 × 1 × 1）。这里每个云团由 3～6 朵拼成（压扁、底下平），按定死的种子在作战区上空 1400～4200 格摆一百多团：
--   · 只在本机有（不碰撞、不挡射线、不投影子），跟着高空风慢慢飘
--   · 只摆离镜头 14 公里以内的（远了交给雾和地形的云层）；每 0.25 秒按距离调透明度：远处淡入、钻进云里淡出隐藏
--     （透明的片叠满整屏会很卡：飞机穿云时那一朵整个藏起来，穿过去再出来）
--   · 没导入 clouds.glb：不摆（Warfx 那几十团球拼的积云照旧有）
local RS = game:GetService("ReplicatedStorage")

local SnowClouds = {}

local PART = {   -- 三块切片（模型坐标：中心、大小）
  X = { c = Vector3.new(0.058, 0, 0), s = Vector3.new(0.6, 1, 1) },
  Y = { c = Vector3.new(0, 0.069, 0), s = Vector3.new(1, 0.596, 1) },
  Z = { c = Vector3.new(0, 0, 0.004), s = Vector3.new(1, 1, 0.751) },
}
local VIEW = 14000     -- 离镜头多远以内才摆（画质低时 9000）
local FADE_FAR = 3000  -- 最远那 3 公里慢慢淡出
local WIND = Vector3.new(6, 0, 2.5)   -- 高空风（格 / 秒）

-- 画质低（手机、或者画质档调在 4 以下）：云少一大半、看得近一点（用户 11-27「再加上体积云和下雪，手机大概率吃不消」）
local function lowGfx(G)
  if G.mobile then return true end
  local ok, lv = pcall(function() return UserSettings():GetService("UserGameSettings").SavedQualityLevel end)
  if ok and lv then
    local n = tonumber(string.match(tostring(lv), "(%d+)$"))   -- Automatic 没有数字
    if n and n <= 3 then return true end
  end
  return false
end
SnowClouds.lowGfx = lowGfx

function SnowClouds.init(G)
  local Map = G.Map
  local TURN = CFrame.Angles(0, math.pi, 0)
  pcall(function() TURN = require(RS:WaitForChild("ImportTurn", 5)).TURN end)
  local folder = nil
  local puffs = {}   -- { pos 中心（不算风）, s 大小, yaw, parts = { 零件… } 或 nil, rel = { 相对中心的 CFrame… }, r 半径 }
  local src = nil

  local function srcParts()
    local imp = RS:FindFirstChild("Imported")
    local sc = imp and imp:FindFirstChild("Scenery")
    local f = sc and sc:FindFirstChild("cloud")
    if not f then return nil end
    local t = {}
    for k in pairs(PART) do
      local p = f:FindFirstChild("N_cloud__" .. k)
      if not p then return nil end
      t[k] = p
    end
    return t
  end

  local function clear()
    if folder then folder:Destroy() end
    folder = nil
    table.clear(puffs)
  end

  local nBuild, nTick, nSpawn = 0, 0, 0   -- 测试、性能面板看
  local function build()
    nBuild += 1
    clear()
    if Map.NAME ~= "snow" then return end
    src = srcParts()
    if not src then return end
    folder = Instance.new("Folder")
    folder.Name = "SnowClouds"
    folder.Parent = workspace
    local R = Random.new(26112)
    local span = 30000
    local low = lowGfx(G)
    VIEW = low and 9000 or 14000
    for _ = 1, (low and 60 or 150) do
      -- 谷上空多一些（交战的地方），外面也有（飞出去还是有云）
      local cx, cz
      if R:NextNumber() < 0.55 then
        cx, cz = R:NextNumber(-9000, 9000), R:NextNumber(-14000, 14000)
      else
        cx, cz = R:NextNumber(-span, span), R:NextNumber(-span, span)
      end
      local base = R:NextNumber(1400, 4200)
      local S = R:NextNumber(500, 1300)
      local yaw0 = R:NextNumber(0, math.pi * 2)
      for i = 1, R:NextInteger(3, 6) do
        local k = (i == 1) and 1 or R:NextNumber(0.55, 0.9)
        local sx = S * k * R:NextNumber(0.9, 1.25)
        local sy = S * k * R:NextNumber(0.42, 0.6)
        local ox, oz = R:NextNumber(-0.55, 0.55) * S, R:NextNumber(-0.4, 0.4) * S
        local c, s = math.cos(yaw0), math.sin(yaw0)
        local pos = Vector3.new(cx + ox * c - oz * s, base + sy * 0.5 + R:NextNumber(0, 0.25) * S * 0.3, cz + ox * s + oz * c)
        table.insert(puffs, { pos = pos, s = Vector3.new(sx, sy, sx * R:NextNumber(0.85, 1.1)), yaw = R:NextNumber(0, math.pi * 2),
          r = math.max(sx, sy) * 0.5, parts = nil })
      end
    end
  end

  local function spawnPuff(P)
    P.parts, P.rel = {}, {}
    for k, d in pairs(PART) do
      local p = src[k]:Clone()
      p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
      p.Size = Vector3.new(d.s.X * P.s.X, d.s.Y * P.s.Y, d.s.Z * P.s.Z)
      p.Transparency = 1
      table.insert(P.parts, p)
      table.insert(P.rel, CFrame.Angles(0, P.yaw, 0) * CFrame.new(d.c.X * P.s.X, d.c.Y * P.s.Y, d.c.Z * P.s.Z) * TURN)
      p.Parent = folder
    end
  end
  local function dropPuff(P)
    for _, p in ipairs(P.parts or {}) do p:Destroy() end
    P.parts, P.rel = nil, nil
  end

  local acc, t0 = 0, os.clock()
  local moveP, moveC = {}, {}
  local tick
  G.frameConn("snowclouds", function(dt)
    if not folder then return end
    acc += dt or 0
    if acc < 0.25 then return end
    acc = 0
    tick(workspace.CurrentCamera.CFrame.Position)
  end)
  -- 一拍：按镜头位置摆近处的、收远处的、调透明度（测试也直接调：G.snowCloudTick）
  tick = function(cam)
    if not folder then return end
    nTick += 1
    local drift = WIND * (os.clock() - t0)
    local made = 0
    table.clear(moveP)
    table.clear(moveC)
    for _, P in ipairs(puffs) do
      local pos = P.pos + drift
      -- 飘出作战区的从另一头回来（±32 公里一圈）
      local wx = ((pos.X + 32000) % 64000) - 32000
      local wz = ((pos.Z + 32000) % 64000) - 32000
      pos = Vector3.new(wx, pos.Y, wz)
      local d = (pos - cam).Magnitude
      if d < VIEW then
        if not P.parts and made < 12 then   -- 一次最多新摆 12 朵（刚开局、飞得快时不一下子卡住）
          spawnPuff(P)
          made += 1
          nSpawn += 1
        end
        if P.parts then
          -- 透明度：贴近（半径的 0.9～2.2 倍）淡掉、钻进去全透明；远处最后 3 公里淡出
          local near = math.clamp((d - P.r * 0.9) / (P.r * 1.3), 0, 1)
          local far = math.clamp((VIEW - d) / FADE_FAR, 0, 1)
          local tr = 1 - near * far
          local cf = CFrame.new(pos)
          for i, p in ipairs(P.parts) do
            if p.Transparency ~= tr then p.Transparency = tr end
            moveP[#moveP + 1] = p
            moveC[#moveC + 1] = cf * P.rel[i]
          end
        end
      elseif P.parts then
        dropPuff(P)
      end
    end
    if #moveP > 0 then workspace:BulkMoveTo(moveP, moveC, Enum.BulkMoveMode.FireCFrameChanged) end
  end
  G.snowCloudTick = function(cam) tick(cam) end   -- 测试用

  G.onMap(function() build() end)
  build()
  -- 进服时 clouds.glb 的块可能还没传到：每 3 秒看一眼，传到了就铺（最多看两分钟）
  task.spawn(function()
    for _ = 1, 40 do
      task.wait(3)
      if Map.NAME == "snow" and not folder and srcParts() then build() end
    end
  end)
  G.snowCloudStats = function()   -- 测试用
    local n, live = #puffs, 0
    for _, P in ipairs(puffs) do if P.parts then live += 1 end end
    local cp = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position
    return { puffs = n, live = live, imported = src ~= nil, builds = nBuild, ticks = nTick, spawned = nSpawn, cam = cp and string.format("%.0f,%.0f,%.0f", cp.X, cp.Y, cp.Z) }
  end
end

return SnowClouds
