-- Roblox全面大战场（客户端）——昼夜更替（用户：改成昼夜更替吧，一直黑天玩起来有点怪；11-18 又说把白天模式去掉、锁定晚上：Config.DayNight.lockNight；
--   11-25：「给沙漠地图做个昼夜更替」——又打开了）
--   钟点在 ReplicatedStorage/DayClock.lua（服务器、客户端同一套：照明弹只在夜里打也看它）：一圈 48 分钟——白天 7:00～17:00 二十八分钟、
--   黄昏四分钟、夜里 19:30～4:30 十二分钟、清晨四分钟；每局开局拨回早上 8 点；PvE 关卡按自己的钟点开局（夜战关卡钉在夜里）
--   用户 11-27：光影照战雷做（黄昏侧光暖、阴影软硬合适、远处空气透视、雪地反光不过曝、夜里月光冷），Apple M3 上要丝滑——
--   · 每张图一套光照（ReplicatedStorage/LightLooks.lua：钢城、沙海、雪山、训练场 × 白天 / 黄昏 / 清晨 / 夜里），所有字段都跟着太阳高度混合：
--     亮度、环境光、天光、太阳颜色、反光、曝光、阴影软硬、大气（浓度、Offset、颜色、霾、太阳周围的光）、泛光、太阳光束、调色；
--     镜头在训练场那块用训练场那套，别处用这一局的战场；纬度（太阳低一点、影子长一点）、全局风按图设
--   · 钟点跳了（每局开局拨回早上、PvE 关卡、测试拨钟）：几个混合权重一秒左右缓过去，不一下跳
--   · 后期效果只在用得上的时候开：太阳光束天黑了关（夜里本来就是 0）、机器跟不上（自动画质 G.perfK 低）也关；
--     远处景深（FarBlur，用户 11-22「远处模糊这样」）地面上照旧开着 0.06、开飞机 0.035，开镜、看光电吊舱、画面卡的时候关
--   开飞机飞得越高大气越淡（用户：飞机视野有点近）。夜视仪（Night.lua）开着时在这上面加亮、变绿，白天开夜视只亮一点点
--   G.dayK()：0 夜里 ～ 1 白天；G.isNight()：天黑了（出生自动开夜视看这个）
local Lighting = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")

local DayNight = {}

function DayNight.init(G)
  local DC = require(RS:WaitForChild("DayClock"))
  local Map = require(RS:WaitForChild("Map"))
  -- 各图的光照参数（服务器 World.lighting 也用）：等不到就报错跳过（init.client.lua 每个模块单独 pcall），别把后面的模块卡死——
  --   等 10 秒（同 init.client.lua 等模块的规矩：用户 11-20 deploy 进不去那次立的；原来等 20 秒，后面的模块跟着多等）
  local llMod = RS:WaitForChild("LightLooks", 10)
  if not llMod then error("缺少 ReplicatedStorage.LightLooks（脚本没换全？）") end
  local LL = require(llMod)
  local RGB = Color3.fromRGB
  local function lc(a, b, t) return a:Lerp(b, t) end
  local function smooth(a, b, v) local t = math.clamp((v - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end

  -- 夜视增亮多少档曝光（用户 11-22：「夜视仪视角沙漠的地面全是白色的」）：草地、土地（亮度约 0.23）加 2.7 档；沙漠全是沙（约 0.5，亮一倍多），
  --   同样 +2.7 档沙地直接过曝成一片白（车里的昼光观瞄镜里就是一片黄）——少加 1.2 档；雪地比沙地还亮（反照率约 0.8）：加得更少。
  --   11-27 换成按图的光照（LightLooks）以后，夜里的基准曝光低了 0.1～0.2 档（钢城 / 训练场 0.55 → 0.45、沙海 0.55 → 0.35、雪山 0.62 → 0.45）：
  --   夜视画面要和原来一样亮——半夜开夜视的总曝光钉在原来的数（夜里基准 + 增亮：0.55 + 2.7、沙海 0.55 + 1.5、雪山 0.62 + 1.1），
  --   增亮 = 这个数减这张图夜里的基准（以后 LightLooks 再调夜里的曝光，夜视也不跟着变暗变亮）
  local NV_EV = { city = 0.55 + 2.7, range = 0.55 + 2.7, sands = 0.55 + 1.5, snow = 0.62 + 1.1 }
  --   11-27 复核：月光也补回去——夜里的月光亮度 2.2 → 1.9～2.0、天光反照 EnvironmentDiffuseScale 0.35 → 0.25～0.3，只钉曝光的话
  --   月光照到的开阔地夜视里暗一点点；开夜视时这两样也按夜里的程度（1 − dayK）往改之前的数（各图都是 2.2 / 0.35）插回去
  local NV_BRIGHT, NV_DIFF = 2.2, 0.35
  local look = nil   -- 现在用哪一套（LightLooks.LOOK 的键）
  local function nvEv()
    local P = LL.LOOK[look] or LL.LOOK.city
    return (NV_EV[look] or NV_EV.city) - P.night.exp
  end

  local dayK, clock = 0, 2.3
  G.dayK = function() return dayK end
  G.isNight = function() return dayK < 0.35 end
  G.clockNow = function() return clock end

  -- 灯光属性只有真变了才写（用户 11-18：一卡一卡的——原来每 0.1 秒把钟点、大气、调色全写一遍，钟点一动太阳就动，阴影、天空跟着重算）；
  --   跟属性现在的值比（不另记一份）：别处（服务器开服时设的那套）改过的也照样改回来
  local function put(obj, prop, v)
    local o = obj[prop]
    local t = typeof(v)
    if t == "number" and type(o) == "number" and math.abs(o - v) < 1e-3 then return end
    if t == "Color3" and typeof(o) == "Color3" and math.abs(o.R - v.R) + math.abs(o.G - v.G) + math.abs(o.B - v.B) < 2e-3 then return end
    obj[prop] = v
  end

  ---------------------------------------------------------------- 纬度自检（LightLooks.LAT）
  -- 昼夜、黄昏权重、夜视、地图上的灯、照明弹都按「6 点日出、18 点日落」算（DayClock.sunAlt）。换纬度要是连日出日落一起挪了
  --   （太阳按季节走的算法：高纬度的夏天 21 点才落山），夜里那套光照就会照在还挂在天上的太阳下——进图、换区块时
  --   在 12 点、6 点、18 点各看一眼太阳（同一帧里拨回来，画面上看不出），6 点、18 点离地平线超过 3°（sin ≈ 0.05）就不用这个纬度，
  --   退回原来的 23 度就停，打一条提示（不再往 0 度退：赤道上正午太阳在头顶，影子比 23 度还短，跟「太阳低、影子长」反着来；
  --   23 度是一直用到 11-27 的，昼夜那时就是对的）。读到的太阳方向没跟着钟点变（GetSunDirection 同一帧里不更新）是「判断不了」：
  --   照用这张图的纬度，等钟点自己走到 17 点 / 18 点（7 点 / 6 点）时再看一眼（watchSun：那时的读数隔了好几帧，是新的）
  local latSeen = {}   -- 纬度 → true / false / "?"（看过一次就记住：Roblox 的算法一局里不会变）
  local function sunY(c, lat)
    Lighting.GeographicLatitude = lat
    Lighting.ClockTime = c
    return Lighting:GetSunDirection().Y
  end
  local function latOk(lat, probe)
    if not probe and latSeen[lat] ~= nil then return latSeen[lat] end
    local c0, l0 = Lighting.ClockTime, Lighting.GeographicLatitude
    local ok, res = pcall(function()
      local f = probe or sunY
      local yN, yE, yW = f(12, lat), f(6, lat), f(18, lat)
      if math.abs(yN - yE) < 1e-3 and math.abs(yN - yW) < 1e-3 then return "?" end
      return math.abs(yE) < 0.05 and math.abs(yW) < 0.05
    end)
    if not probe then pcall(function() Lighting.ClockTime, Lighting.GeographicLatitude = c0, l0 end) end
    if not ok then res = "?" end
    if not probe then latSeen[lat] = res end
    return res
  end
  local warned = {}
  local function latWarn(want, why)
    if warned[want] then return end
    warned[want] = true
    warn("[全面大战场] 纬度 " .. tostring(want) .. "°：" .. why .. "，退回 " .. tostring(LL.LAT0)
      .. "°（太阳高一点、影子短一点；昼夜照旧按 6 点日出、18 点日落）。要换纬度改 ReplicatedStorage/LightLooks.lua 的 LAT")
  end
  local function pickLat(want, probe)
    if want == LL.LAT0 then return want end
    if latOk(want, probe) ~= false then return want end   -- true 看过了没问题；"?" 判断不了：照用这张图的纬度
    if not probe then latWarn(want, "6 点、18 点太阳不在地平线上（Roblox 按这个纬度把日出日落挪了）") end
    return LL.LAT0
  end
  G.dnLatPick = pickLat   -- 测试用：pickLat(想要的纬度, 假的太阳（钟点, 纬度）→ 太阳方向的 Y)

  -- 换一套（换图、在训练场和战场之间瞬移）：纬度、全局风跟着换。风只在这时写一次——暴风雨（Warfx.lua）在它的基础上往大了插：
  --   基数放在 G.windBase，暴风雨里换图、换区块时 Warfx 跟着重新取（原来只在暴风雨开始那一下记一次 GlobalWind：新的风被旧基数插出来的值盖掉）
  local lat = LL.LAT0
  local function applyLook(key)
    look = key
    lat = pickLat(LL.LAT[key] or LL.LAT0)
    local w = LL.WIND[key]
    if w then
      G.windBase = w
      pcall(function() workspace.GlobalWind = w end)
    end
  end
  -- 钟点自己走到 6 点、18 点（日出、日落）时看一眼太阳：进图时判断不了的（"?"）在这儿补上。在写这一次的钟点之前读——
  --   ClockTime 还是上一次更新写的（隔了好几帧）；离地平线超过 4°（sin ≈ 0.07）就退回 23 度（一局只换这一次，打提示）。
  --   11-27 复核：每局开局拨回 8 点，18 点要到开局后二十六七分钟才到——真按纬度挪了日落的话，17～18 点黄昏那套光照已经照在还挂得老高的太阳上，
  --   18 点一判纬度一换，太阳在日落这个最显眼的时候跳一下。所以 17 点（还有 7 点）先看一眼：「6 点升 18 点落」的太阳（不管纬度怎么歪）
  --   离落山一小时最多 15° 高、也不会已经落下去；读到高过 20° 或者低过 −2°（按季节走的夏天 48° 那里约 27°）就早一个钟头退回，
  --   黄昏那套还没怎么上来（权重 0.14）。在这个范围里不算数（判不准），照旧等 6 点 / 18 点那一眼
  local function watchSun()
    if lat == LL.LAT0 or latSeen[lat] ~= "?" then return end
    local c = Lighting.ClockTime
    local horizon = math.abs(c - 6) <= 0.05 or math.abs(c - 18) <= 0.05
    local hourOff = math.abs(c - 7) <= 0.05 or math.abs(c - 17) <= 0.05
    if not horizon and not hourOff then return end
    if math.abs(Lighting.GeographicLatitude - lat) > 1e-3 then return end
    local ok, y = pcall(function() return Lighting:GetSunDirection().Y end)
    if not ok or type(y) ~= "number" then return end
    if horizon then
      if math.abs(y) <= 0.07 then
        latSeen[lat] = true
        return
      end
    elseif y <= 0.342 and y >= -0.035 then   -- sin 20°、sin −2°
      return
    end
    latSeen[lat] = false
    latWarn(lat, string.format("%.2f 点太阳离地平线 %.0f°（Roblox 按这个纬度把日出日落挪了）", c, math.deg(math.asin(math.clamp(y, -1, 1)))))
    lat = LL.LAT0
  end

  -- 手机、自己把画质调到 3 档以下的：太阳光束不开（少一遍整屏后期；Roblox 画质 4 以下本来也没有阴影）
  local lowGfx = G.mobile == true
  pcall(function()
    local lv = UserSettings():GetService("UserGameSettings").SavedQualityLevel
    local n = tonumber(string.match(tostring(lv), "(%d+)$"))
    if n and n <= 3 then lowGfx = true end
  end)

  ---------------------------------------------------------------- 每 0.1 秒更新一次
  local EASE = 0.8   -- 钟点跳了（每局开局拨回早上、PvE 关卡、测试拨钟）：混合权重按这个时间常数缓过去（秒）；平常钟点走得慢，只落后一点点
  local vk, vw, vt, eased = 0, 0, 0, false   -- 缓过的 dayK、黄昏权重、太阳颜色的黄昏权重
  local cur = {}   -- 混合好的这一套（复用的表）
  local acc = 1
  local function step(dt)
    acc += dt
    if acc < 0.1 then return end   -- 一秒十次就够顺
    local h = math.min(acc, 1)
    acc = 0
    clock = DC.clock()   -- 锁定晚上（lockNight）、PvE 钉住的钟点（DayFix）、跨局走的（DayT0）都在 DayClock 里
    local alt = DC.sunAlt(clock)   -- 太阳高度（−1 半夜 ～ 1 正午）
    dayK = DC.dayK(clock)
    local tw, twT = LL.twW(alt), LL.twTop(alt)
    local cam = workspace.CurrentCamera
    local key = LL.keyFor(Map, cam and cam.CFrame.Position)
    if key ~= look then
      applyLook(key)
      eased = false   -- 换图、换区块是瞬移过去的：光照直接到位
    end
    watchSun()
    if eased then
      local a = 1 - math.exp(-h / EASE)
      vk += (dayK - vk) * a
      vw += (tw - vw) * a
      vt += (twT - vt) * a
      if math.abs(dayK - vk) < 2e-3 then vk = dayK end
      if math.abs(tw - vw) < 2e-3 then vw = tw end
      if math.abs(twT - vt) < 2e-3 then vt = twT end
    else
      vk, vw, vt, eased = dayK, tw, twT, true
    end
    local v = LL.at(key, vk, vw, vt, clock < 12, cur)   -- 上午用清晨那份、下午用黄昏那份
    -- 开飞机飞得越高大气越淡、雾越远（用户：飞机视野有点近）
    local hk = (G.fly and cam) and smooth(150, 1800, cam.CFrame.Position.Y) or 0
    -- 夜视仪、热成像（G.nvLight），坦克瞄准镜、车里观瞄设备的夜视档（G.sightNv / G.opticNv：原来开着瞄准镜时夜视仪让出画面、增亮也跟着撤了，镜里的夜视档一片墨绿）
    local nv = G.nvLight == true or G.sightNv == true or G.opticNv == true
    local nk = 1 - vk
    local wk = G.weather and G.weather.k or 0   -- 暴风雨（Warfx.lua）：雾变近、大气变浑
    pcall(function()
      -- 太阳 / 月亮的位置分步挪：每格 0.02 小时（游戏里 1.2 分钟，现实里一两秒一格，影子挪 0.3°，看不出跳）——
      --   太阳一动整张阴影图都要重算，原来每 0.1 秒挪一下（用户 11-18「一卡一卡的」；11-25「特别卡」）
      put(Lighting, "ClockTime", math.floor(clock / 0.02 + 0.5) * 0.02)
      put(Lighting, "GeographicLatitude", lat)
      local amb, oamb, exp, bright, diff = v.amb, v.oamb, v.exp, v.bright, v.diff
      if nv then   -- 夜视：本地增亮（白天只亮一点点；沙漠、雪地少加，见 nvEv）；月光、天光反照补回改之前的（NV_BRIGHT）
        exp += nvEv() * nk + 0.25 * vk
        amb, oamb = lc(amb, RGB(52, 60, 56), nk), lc(oamb, RGB(96, 110, 100), nk)
        bright = bright + (NV_BRIGHT - bright) * nk
        diff = diff + (NV_DIFF - diff) * nk
      end
      put(Lighting, "Brightness", bright)
      -- 照明弹（Warfx.lua 的 G.illum）：附近有照明弹在烧，整片地亮起来——环境光往暖白抬、曝光加一点，跟着它一闪一闪
      local il = G.illum and G.illum.k or 0
      if il > 0.01 then
        local kk = math.min(il, 1)
        oamb = lc(oamb, RGB(176, 166, 148), 0.55 * kk)
        amb = lc(amb, RGB(84, 78, 70), 0.45 * kk)
        exp += 0.3 * il
      end
      put(Lighting, "Ambient", amb)
      put(Lighting, "OutdoorAmbient", oamb)
      put(Lighting, "ExposureCompensation", exp)
      put(Lighting, "ColorShift_Top", v.top)
      put(Lighting, "ColorShift_Bottom", v.bot)
      put(Lighting, "EnvironmentDiffuseScale", diff)
      put(Lighting, "EnvironmentSpecularScale", v.spec)
      -- 影子：白天收紧（边缘清楚又不抖）、黄昏软一点、夜里（月光、灯光）更软
      put(Lighting, "ShadowSoftness", v.shadow)
      -- 老式的雾放到十万格（有 Atmosphere 时 Roblox 按大气算远处，这个基本不起作用；没有大气的时候也别挡）
      put(Lighting, "FogColor", v.acol)
      put(Lighting, "FogEnd", 100000 * (1 - 0.7 * wk))
    end)
    pcall(function()
      local atm = Lighting:FindFirstChildOfClass("Atmosphere")
      if not atm then return end
      local dens = v.dens * (1 - 0.5 * hk)
      if nv then dens = math.max(0.035, dens * 0.6) end
      put(atm, "Density", dens + 0.12 * wk)
      put(atm, "Offset", v.off)
      put(atm, "Color", v.acol)
      put(atm, "Decay", v.adec)
      put(atm, "Glare", v.glare)
      put(atm, "Haze", v.haze * (1 - 0.5 * hk) + 1.2 * wk)
    end)
    pcall(function()
      local bloom = Lighting:FindFirstChild("NightBloom")
      if bloom then
        put(bloom, "Intensity", v.bloomI)
        put(bloom, "Threshold", v.bloomT)
        put(bloom, "Size", v.bloomS)
      end
      local cc = Lighting:FindFirstChild("NightGrade")
      if cc then
        put(cc, "Brightness", v.ccB)
        put(cc, "Contrast", v.ccC)
        put(cc, "Saturation", v.ccS)
        put(cc, "TintColor", v.ccTint)
      end
      -- 太阳光束（对着太阳看时从云边、车边、山脊透出来的光）：太阳在天上才有，黄昏最明显；夜里是 0——整个关掉，省一遍后期；
      --   开着夜视只留三成；机器跟不上（自动画质降下来）、手机 / 低画质也关
      local rays = Lighting:FindFirstChild("SunShafts")
      if rays then
        local ri = v.rays * (nv and 0.3 or 1)
        local on = ri > 0.004 and (G.perfK or 1) >= 0.7 and not lowGfx
        if rays.Enabled ~= on then rays.Enabled = on end
        if on then
          put(rays, "Intensity", ri)
          put(rays, "Spread", v.raysSpread)
        end
      end
    end)
  end
  -- 太阳光束（客户端自己的后期效果：每个人本地加，服务器的 Lighting 里没有）
  pcall(function()
    if not Lighting:FindFirstChild("SunShafts") then
      local r = Instance.new("SunRaysEffect")
      r.Name = "SunShafts"
      r.Intensity, r.Spread = 0, 0.6
      r.Enabled = false
      r.Parent = Lighting
    end
  end)
  G.stepDayNight = step
  step(1)
  -- 测试用：现在用的哪一套、纬度、风、混合好的数、缓过的权重
  G.lightLook = function() return { key = look, lat = lat, wind = LL.WIND[look], v = cur, vk = vk, vw = vw, vt = vt } end

  -- 远处模糊（景深，用户 11-22：「视野给我改成无限远好了，然后远处模糊这样」）：近处清楚、越远越糊（Roblox 景深的对焦距离、清楚范围最多 200 + 50 格）；
  --   要看清远处的时候关掉：步兵开镜 / 举枪瞄准、望远镜、坦克瞄准镜、车里的观瞄设备、飞机光电吊舱、阵亡镜头（它自己有景深）；画面卡（自动画质低）也关
  -- 用户 11-25「画质一般」：原来远处糊 0.2——两百五十格（九十米）以外整片发糊，一两公里外的坦克、房子、山都是一团，画面看着「低清」；
  --   压到 0.06（只把很远的地平线柔一点）；开飞机 0.035（看的本来就是几公里外：糊得更轻）。
  --   11-27 光影那一版把地面上的整个关了（省一遍整屏后期），审查时恢复：这是用户要过的，远近的层次一半靠它、一半靠大气（LightLooks 只有 0.07～0.09）；
  --   机器跟不上的时候照样先关它（G.perfK < 0.7）
  local far = Instance.new("DepthOfFieldEffect")
  far.Name = "FarBlur"
  far.FocusDistance, far.InFocusRadius, far.NearIntensity, far.FarIntensity = 200, 50, 0, 0.06
  far.Parent = Lighting
  G.farBlur = far   -- 测试用
  G.frameConn("FarBlur", function()
    local dr, fl = G.drive, G.fly
    local sharp = G.scopeOn == true or G.fpsAiming == true or (dr ~= nil and (dr.sight or dr.eo)) or G.interiorOptic ~= nil
      or (fl ~= nil and fl.eo == true) or (G.killcamOn ~= nil and G.killcamOn()) or (G.perfK or 1) < 0.7
    local want = not sharp
    if far.Enabled ~= want then far.Enabled = want end
    if want then
      local k = fl and 0.035 or 0.06
      if math.abs(far.FarIntensity - k) > 0.005 then far.FarIntensity = k end
    end
  end)
end

return DayNight
