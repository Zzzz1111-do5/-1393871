-- 全面大战场（客户端）——雪山地图的地面和下雪
--   用户 11-26 晚：「我发你的那个这里面的雪非常细节 …… 地面用我发你的这个雪」——99.Miles 冬季树包里那张积雪贴图（颜色 + 法线：一团团鼓起来的雪），
--   化雪的泥地（雪和泥混在一起）那张给路面、车辙。tools/snow/winter.py 把两张贴图各放在一块薄片上（models/scenery/winter.glb 的
--   N_snowtex__Body、N_slushtex__Body）：Studio「导入 3D」时贴图会上传成资源；这里读那两块的 SurfaceAppearance，做成 MaterialVariant，
--   用 MaterialService:SetBaseMaterialOverride 换掉地形的 Snow、Ground（只在雪山；换到别的图换回来）。
--   哪一步不让做（老版本 Roblox 不许运行时改材质、没导入 winter.glb）：照旧用 Roblox 自带的雪，输出窗口说一声怎么在 Studio 里手动设
--   天空：银河夜空、木卫三当月亮、太阳（models/snow/sky.glb 的七块贴图，见下面「天空」）
--   下雪：镜头上方一块看不见的板往下飘雪花（世界坐标，不跟着镜头晃）；镜头高过 1500 格（开飞机）就停
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SnowLook = {}

local LOOKS = {
  { key = "snowtex", mat = Enum.Material.Snow, name = "WinterSnow", tile = 18 },
  { key = "slushtex", mat = Enum.Material.Ground, name = "WinterSlush", tile = 14 },
}

function SnowLook.init(G)
  local Map = G.Map
  local MS = game:GetService("MaterialService")
  local overridden = {}
  local warned = false

  local function texOf(key)
    local imp = RS:FindFirstChild("Imported")
    local sc = imp and imp:FindFirstChild("Scenery")
    local f = sc and sc:FindFirstChild(key)
    local p = f and f:FindFirstChildWhichIsA("BasePart")
    if not p then return nil end
    local sa = p:FindFirstChildOfClass("SurfaceAppearance")
    local t = {}
    if sa then
      pcall(function() t.color, t.normal, t.rough = sa.ColorMap, sa.NormalMap, sa.RoughnessMap end)
    end
    if (t.color or "") == "" and p:IsA("MeshPart") then pcall(function() t.color = p.TextureID end) end
    if (t.color or "") == "" then return nil end
    return t
  end

  local function revert()
    for mat in pairs(overridden) do
      pcall(function() MS:SetBaseMaterialOverride(mat, "") end)
    end
    table.clear(overridden)
  end

  local function apply()
    revert()
    if Map.NAME ~= "snow" then return end
    local missing = {}
    for _, L in ipairs(LOOKS) do
      local t = texOf(L.key)
      if not t then
        table.insert(missing, L.key)
      else
        local ok, err = pcall(function()
          local mv = MS:FindFirstChild(L.name) or Instance.new("MaterialVariant")
          mv.Name = L.name
          mv.BaseMaterial = L.mat
          mv.ColorMap = t.color
          if (t.normal or "") ~= "" then mv.NormalMap = t.normal end
          if (t.rough or "") ~= "" then mv.RoughnessMap = t.rough end
          mv.StudsPerTile = L.tile
          mv.Parent = MS
          MS:SetBaseMaterialOverride(L.mat, L.name)
          overridden[L.mat] = true
        end)
        if not ok and not warned then
          warned = true
          warn("[全面大战场] 雪山的地面贴图换不上（" .. tostring(err) .. "）：可以在 Studio 里手动设——MaterialService 里新建 MaterialVariant「WinterSnow」"
            .. "（BaseMaterial 选 Snow，ColorMap / NormalMap 用 Imported.Scenery.snowtex 那块的贴图），再把 MaterialService 的 Snow 换成 WinterSnow")
        end
      end
    end
    if #missing > 0 and not warned then
      warned = true
      warn("[全面大战场] 雪山的地面雪贴图还没导入（" .. table.concat(missing, "、") .. "）：Studio「导入 3D」导入 models/scenery/winter.glb（冬季树包，树、灌木也在里面）")
    end
  end

  ---------------------------------------------------------------- 天空：银河夜空（天空盒六个面）、木卫三当月亮、太阳
  --   用户 11-26 晚给的三个 Sketchfab 模型（Night Sky Visible Spectrum Monochromatic、Ganymede、The Sun）：tools/snow/sky.py 切成七张图，
  --   各贴在一块薄片上（models/snow/sky.glb：N_skyft__Body …、N_moontex__Body、N_suntex__Body），导入时上传；这里读出来设到 Lighting 的 Sky 上
  --   昼夜照旧是 DayNight.lua 走；星空天空盒只在天黑（太阳落山后、天亮前）挂上，白天换回原来的天空（不然白天也是一片黑底星空）。离开雪山时还原
  local SKY = { SkyboxFt = "skyft", SkyboxBk = "skybk", SkyboxLf = "skylf", SkyboxRt = "skyrt", SkyboxUp = "skyup", SkyboxDn = "skydn",
    MoonTextureId = "moontex", SunTextureId = "suntex" }
  local BOX = { "SkyboxFt", "SkyboxBk", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SkyboxDn" }
  local skyOrig, skyIds, skyNight = nil, nil, nil
  local function isNight()
    local h = game:GetService("Lighting").ClockTime
    return h < 5.6 or h > 18.4
  end
  -- 天黑天亮时换天空盒（每半秒看一次）
  local function skyBox()
    if not skyOrig or not skyIds then return end
    local n = isNight()
    if n == skyNight then return end
    skyNight = n
    local sky = game:GetService("Lighting"):FindFirstChildOfClass("Sky")
    if not sky then return end
    pcall(function()
      for _, prop in ipairs(BOX) do sky[prop] = n and skyIds[prop] or skyOrig[prop] end
    end)
  end
  local function applySky()
    local L = game:GetService("Lighting")
    local sky = L:FindFirstChildOfClass("Sky")
    if not sky then return false end
    if Map.NAME ~= "snow" then
      if skyOrig then
        for prop, v in pairs(skyOrig) do pcall(function() sky[prop] = v end) end
        skyOrig, skyIds, skyNight = nil, nil, nil
      end
      return true
    end
    local ids = {}
    for prop, key in pairs(SKY) do
      local t = texOf(key)
      if not t then return false end   -- 七张少一张都不换（天空盒缺一面难看）
      ids[prop] = t.color
    end
    local ok = pcall(function()
      skyOrig = skyOrig or { StarCount = sky.StarCount, MoonAngularSize = sky.MoonAngularSize, SunAngularSize = sky.SunAngularSize }
      for prop in pairs(SKY) do skyOrig[prop] = skyOrig[prop] or sky[prop] end
      skyIds = ids
      sky.MoonTextureId, sky.SunTextureId = ids.MoonTextureId, ids.SunTextureId
      skyNight = nil
      skyBox()
      sky.StarCount = 1200        -- 银河星空自己有星星：Roblox 自带的星星少放一点（一闪一闪的点缀）
      sky.MoonAngularSize = 9     -- 木卫三：大一点、看得清上面的纹路
      sky.SunAngularSize = 14
      sky.CelestialBodiesShown = true
    end)
    return ok
  end
  G.snowSkyOn = function() return skyOrig ~= nil, skyNight end   -- 测试用

  ---------------------------------------------------------------- 下雪

  local board, emitter = nil, nil
  local rateMax = 400   -- 每秒几片：引擎每个发射器最多 400（手机 100）；画质低的少下（见下面）
  local function snowOn(on)
    if on and not board then
      board = Instance.new("Part")
      board.Name = "SnowFall"
      board.Anchored, board.CanCollide, board.CanQuery, board.CanTouch, board.CastShadow = true, false, false, false, false
      board.Transparency = 1
      board.Size = Vector3.new(260, 1, 260)
      emitter = Instance.new("ParticleEmitter")
      -- 雪花是柔边的白色圆点（Roblox 自带的 explosion01_implosion_main）：原来的 sparkles_main 是八角星，近看像卡通星星（用户 11-27 照战雷做）
      emitter.Texture = "rbxasset://textures/particles/explosion01_implosion_main.dds"
      emitter.Color = ColorSequence.new(Color3.fromRGB(246, 248, 255))
      emitter.LightEmission = 0
      emitter.LightInfluence = 1   -- 受光：夜里是月光照着的灰蓝，不自己发亮
      emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22, 0.06), NumberSequenceKeypoint.new(1, 0.2, 0.05) })   -- 0.16～0.28 格
      emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.08, 0.15), NumberSequenceKeypoint.new(0.85, 0.2), NumberSequenceKeypoint.new(1, 1) })
      emitter.Lifetime = NumberRange.new(9, 13)
      -- 画质低（手机、画质档 4 以下）雪下得稀一些
      local low = G.mobile == true
      pcall(function()
        local lv = UserSettings():GetService("UserGameSettings").SavedQualityLevel
        local n = tonumber(string.match(tostring(lv), "(%d+)$"))
        if n and n <= 3 then low = true end
      end)
      rateMax = low and 150 or 400
      emitter.Rate = rateMax
      emitter.Speed = NumberRange.new(5, 9)
      emitter.SpreadAngle = Vector2.new(18, 18)
      emitter.EmissionDirection = Enum.NormalId.Bottom
      -- 一点风：顺着雪山的全局风（LightLooks.WIND.snow，烟、尘也往这边飘）斜着飘，大小同原来（水平 2.8 格/秒²）
      local wdir = Vector3.new(2.5, 0, 1.2)
      pcall(function()
        local w = require(RS:WaitForChild("LightLooks", 5)).WIND.snow
        if w and w.Magnitude > 0.1 then wdir = w end
      end)
      wdir = wdir.Unit * 2.77
      emitter.Acceleration = Vector3.new(wdir.X, -1.2, wdir.Z)
      emitter.RotSpeed = NumberRange.new(-60, 60)
      emitter.Rotation = NumberRange.new(0, 360)
      emitter.Drag = 0.4
      emitter.Parent = board
      board.Parent = workspace
    elseif not on and board then
      board:Destroy()
      board, emitter = nil, nil
    end
  end
  G.snowFallOn = function() return board ~= nil end   -- 测试用

  local acc = 0
  local skyAcc = 0
  G.frameConn("snowlook", function(dt)
    skyAcc += dt or 0
    if skyAcc > 0.5 then
      skyAcc = 0
      skyBox()
    end
    if not board then return end
    acc += dt or 0
    local cp = workspace.CurrentCamera.CFrame.Position
    board.CFrame = CFrame.new(cp.X, cp.Y + 70, cp.Z)
    if acc > 0.5 then
      acc = 0
      local want = cp.Y < (Map.PLAIN or 12) + 1500
      if emitter.Enabled ~= want then emitter.Enabled = want end
      -- 机器跟不上（自动画质 G.perfK 降下来）雪跟着稀一点；差一成以上才改（粒子发射器的属性少改：改一次就要重排）
      local rate = math.floor(rateMax * math.clamp(G.perfK or 1, 0.5, 1) + 0.5)
      if math.abs(emitter.Rate - rate) > rateMax * 0.1 then emitter.Rate = rate end
    end
  end)

  ---------------------------------------------------------------- 车辆残骸（Map.PROPS.wreck，用户 11-27「车辆残骸……都很少」）：真车模型（Imported.Veh）烧黑——
  --   贴图去掉、底色焦黑、锈蚀金属；炮塔转个角度、车身歪一点；没导入那型车就用零件拼个车壳。碰撞盒是服务器上看不见的那块（SnowBuild）
  local wreckF = nil
  local TURN = CFrame.Angles(0, math.pi, 0)
  pcall(function() TURN = require(RS:WaitForChild("ImportTurn", 5)).TURN end)
  local function buildWrecks()
    if wreckF then wreckF:Destroy() wreckF = nil end
    if Map.NAME ~= "snow" or not (Map.PROPS and Map.PROPS.wreck) then return end
    local okM, IM = pcall(function() return require(RS:WaitForChild("ImportedMeta", 5)) end)
    local imp = RS:FindFirstChild("Imported")
    local vf = imp and imp:FindFirstChild("Veh")
    wreckF = Instance.new("Folder")
    wreckF.Name = "SnowWrecks"
    for i, w in ipairs(Map.PROPS.wreck) do
      local x, z, yaw, key, tur, tilt = w[1], w[2], w[3], w[4], w[5], w[6]
      local y = Map.ground(x, z)
      local base = CFrame.new(x, y - 0.7, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, tilt * 0.7)
      local info = okM and IM and IM.m and IM.m[key]
      local src = vf and vf:FindFirstChild(key)
      local made = 0
      if info and src then
        local tpiv = info.tur and Vector3.new(info.tur[1], info.tur[2], info.tur[3]) or Vector3.zero
        local tcf = base * CFrame.new(tpiv) * CFrame.Angles(0, tur, 0)
        for name, p in pairs(info.parts) do
          local part = src:FindFirstChild("V_" .. key .. "__" .. name)
          if part and part:IsA("BasePart") and p.k ~= "int" and p.k ~= "cav" and p.k ~= "glass" then
            local mp = part:Clone()
            mp.Anchored, mp.CanCollide, mp.CanQuery, mp.CanTouch = true, false, false, false
            mp.Size = Vector3.new(p.s[1], p.s[2], p.s[3])
            for _, c in ipairs(mp:GetChildren()) do
              if c:IsA("SurfaceAppearance") or c:IsA("Decal") or c:IsA("Texture") then c:Destroy() end
            end
            pcall(function() mp.TextureID = "" end)
            local k = 0.85 + ((i * 7 + #name) % 5) * 0.06
            mp.Color = Color3.fromRGB(math.floor(38 * k), math.floor(33 * k), math.floor(30 * k))
            mp.Material = Enum.Material.CorrodedMetal
            local c = Vector3.new(p.c[1], p.c[2], p.c[3])
            if p.g == "Turret" or p.g == "Gun" or p.g == "Rws" or p.g == "RwsGun" then
              mp.CFrame = tcf * CFrame.new(c - tpiv) * TURN
            else
              mp.CFrame = base * CFrame.new(c) * TURN
            end
            mp.Parent = wreckF
            made += 1
          end
        end
      end
      if made == 0 then   -- 没导入：零件拼一个烧黑的车壳（车体、炮塔、炮管、履带）
        local L, W, H = 24, 11, 5
        local function bx(size, cf)
          local p = Instance.new("Part")
          p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
          p.Size, p.CFrame, p.Color, p.Material = size, cf, Color3.fromRGB(36, 32, 30), Enum.Material.CorrodedMetal
          p.Parent = wreckF
        end
        bx(Vector3.new(W, H, L), base * CFrame.new(0, H / 2 + 1, 0))
        for _, sx in ipairs({ -1, 1 }) do bx(Vector3.new(2.6, 3.4, L + 1), base * CFrame.new(sx * (W / 2 + 1.1), 1.7, 0)) end
        local t = base * CFrame.new(0, H + 1, 1) * CFrame.Angles(0, tur, 0)
        bx(Vector3.new(8, 3.2, 9), t * CFrame.new(0, 1.6, 0))
        bx(Vector3.new(0.9, 0.9, 14), t * CFrame.new(0, 1.8, -10) * CFrame.Angles(-0.12, 0, 0))
      end
    end
    wreckF.Parent = workspace
  end
  G.snowWrecks = function() return wreckF and #wreckF:GetChildren() or 0 end   -- 测试用

  local function onMap()
    apply()
    applySky()
    snowOn(Map.NAME == "snow")
    buildWrecks()
  end
  G.onMap(onMap)
  onMap()
  -- 进服时 winter.glb、sky.glb 的块可能还在往下传：过一会儿再试一次（只试没换上的）
  task.delay(20, function()
    if Map.NAME ~= "snow" then return end
    if next(overridden) == nil then apply() end
    if not skyOrig then applySky() end
    buildWrecks()   -- 车模型可能刚传到：重摆一遍（用真模型）
  end)
  G.snowLookApplied = function() local n = 0 for _ in pairs(overridden) do n += 1 end return n end   -- 测试用
end

return SnowLook
