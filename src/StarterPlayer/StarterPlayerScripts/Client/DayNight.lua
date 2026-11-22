-- Roblox全面大战场（客户端）——昼夜更替（用户：改成昼夜更替吧，一直黑天玩起来有点怪；11-18 又说把白天模式去掉、锁定晚上：Config.DayNight.lockNight）
--   每局从早上 7:30 开始，一圈 24 分钟（Config.DayNight.period）：白天长（7:30～17:30 约 13 分钟）、黄昏 / 清晨各一分多钟、夜里不到 6 分钟；
--   时间按服务器开局时记下的 workspace 属性 DayT0 和服务器时钟算，所有人看到的一样
--   跟着太阳高度渐变：亮度、环境光、天空光的颜色（黄昏偏橙）、雾、大气（白天通透、看得远）、泛光和调色（夜里冷蓝、白天中性）；
--   开飞机飞得越高大气越淡（用户：飞机视野有点近）。夜视仪（Night.lua）开着时在这上面加亮、变绿，白天开夜视只亮一点点
--   G.dayK()：0 夜里 ～ 1 白天；G.isNight()：天黑了（出生自动开夜视看这个）
local Lighting = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")

local DayNight = {}

function DayNight.init(G)
  local Config = require(RS:WaitForChild("Config"))
  local DN = Config.DayNight or {}
  local PERIOD = DN.period or 24 * 60
  local RGB = Color3.fromRGB
  local function lerp(a, b, t) return a + (b - a) * t end
  local function lc(a, b, t) return a:Lerp(b, t) end
  local function smooth(a, b, v) local t = math.clamp((v - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end

  -- 一圈里的真实时间比例 → 钟点（单调增，超过 24 的取余）
  local KEY = { { 0, 7.5 }, { 0.55, 17.5 }, { 0.62, 19.3 }, { 0.86, 28.7 }, { 0.93, 30.3 }, { 1, 31.5 } }
  local function clockAt(f)
    for i = 1, #KEY - 1 do
      local a, b = KEY[i], KEY[i + 1]
      if f <= b[1] then return (a[2] + (b[2] - a[2]) * (f - a[1]) / (b[1] - a[1])) % 24 end
    end
    return KEY[#KEY][2] % 24
  end
  local function serverNow()
    local ok, t = pcall(function() return workspace:GetServerTimeNow() end)
    return ok and t or os.clock()
  end

  -- 夜里 / 白天两套（夜里照 World.lighting 原来那套）
  -- 大气（用户 11-22：「视野给我改成无限远好了，然后远处模糊这样」）：原来夜里 0.21、白天 0.17，几公里外就灰成一片；
  --   放淡到 0.085 / 0.07、霾减半，远处的山、岛、舰队看得见，远处的「看不清」改成下面的景深模糊（FarBlur）
  local NIGHT = { bright = 2.2, amb = RGB(14, 17, 24), oamb = RGB(38, 45, 62), top = RGB(140, 160, 210), bot = RGB(8, 10, 16), diff = 0.35, spec = 0.9, exp = 0.55,
    fog = RGB(16, 20, 30), dens = 0.085, acol = RGB(44, 54, 76), adec = RGB(12, 15, 24), glare = 0.15, haze = 0.5,
    bloomI = 1.1, bloomT = 1.05, ccSat = -0.12, ccCon = 0.14, ccTint = RGB(222, 232, 255) }
  local DAY = { bright = 3.0, amb = RGB(78, 80, 86), oamb = RGB(132, 134, 140), top = RGB(255, 248, 236), bot = RGB(42, 38, 32), diff = 1, spec = 1, exp = 0,
    fog = RGB(176, 194, 214), dens = 0.07, acol = RGB(196, 208, 224), adec = RGB(96, 112, 136), glare = 0.25, haze = 0.3,
    bloomI = 0.35, bloomT = 1.6, ccSat = 0.04, ccCon = 0.07, ccTint = RGB(255, 255, 255) }
  -- 夜视增亮多少档曝光（用户 11-22：「夜视仪视角沙漠的地面全是白色的」）：海岛的地面是草（亮度约 0.23），沙漠全是沙（约 0.5，亮一倍多），
  --   同样 +2.7 档沙地直接过曝成一片白（车里的昼光观瞄镜里就是一片黄）；沙漠少加 1.2 档，沙地落在跟海岛草地差不多的亮度
  local Map = require(RS:WaitForChild("Map"))
  local function isDesert() return Map.desert or Map.DESERT end   -- 沙漠风暴（MapDesert）、沙海（MapSands）
  local function nvEv() return isDesert() and 1.5 or 2.7 end
  local DUSK = { top = RGB(255, 168, 108), fog = RGB(206, 150, 120), acol = RGB(228, 160, 120), adec = RGB(170, 86, 58) }
  -- 沙漠图：夜里的天光、雾偏暖褐（沙尘），白天是发白的黄沙天、看得没那么远。地图是开服后第一个玩家选的：进服时还没定、
  --   选了沙漠才换过来（init.client.lua 的 G.onMap），所以这里换地图时再套一次（服务器一局里不会从沙漠换回海岛，套一次就够）
  local desertSet = false
  local function desertPalette()
    if desertSet or not isDesert() then return end
    desertSet = true
    NIGHT.fog, NIGHT.acol, NIGHT.adec, NIGHT.oamb = RGB(26, 22, 20), RGB(70, 60, 54), RGB(22, 17, 14), RGB(50, 46, 48)
    NIGHT.ccTint = RGB(240, 234, 236)
    DAY.fog, DAY.acol, DAY.adec, DAY.dens, DAY.haze = RGB(214, 196, 168), RGB(222, 206, 178), RGB(168, 132, 96), 0.22, 1.4
    DAY.ccTint, DAY.ccSat = RGB(255, 246, 232), 0
  end
  desertPalette()
  if G.onMap then G.onMap(desertPalette) end

  local dayK, clock = 0, 2.3
  G.dayK = function() return dayK end
  G.isNight = function() return dayK < 0.35 end
  G.clockNow = function() return clock end

  -- 灯光属性只有真变了才写（用户 11-18：一卡一卡的——原来每 0.1 秒把钟点、大气、调色全写一遍，钟点一动太阳就动，阴影、天空跟着重算）；
  --   跟属性现在的值比（不另记一份）：别处（服务器开服时的那套夜里灯光）改过的也照样改回来
  local function put(obj, prop, v)
    local o = obj[prop]
    local t = typeof(v)
    if t == "number" and type(o) == "number" and math.abs(o - v) < 1e-3 then return end
    if t == "Color3" and typeof(o) == "Color3" and math.abs(o.R - v.R) + math.abs(o.G - v.G) + math.abs(o.B - v.B) < 2e-3 then return end
    obj[prop] = v
  end
  local acc = 1
  local function step(dt)
    acc += dt
    if acc < 0.1 then return end   -- 一秒十次就够顺
    acc = 0
    if DN.lockNight then   -- 锁定晚上（用户：把白天模式去掉）：钟点停在半夜，太阳高度在地平线下面，灯光就是夜里那一套
      clock = DN.clock or 2.3
    else
      local t0 = workspace:GetAttribute("DayT0")
      if type(t0) ~= "number" then t0 = 0 end
      local f = ((serverNow() - t0) / PERIOD) % 1
      clock = clockAt(f)
    end
    local alt = math.sin((clock - 6) / 12 * math.pi)   -- 太阳高度（−1 半夜 ～ 1 正午）
    dayK = smooth(-0.08, 0.22, alt)
    local dusk = (alt > -0.18 and alt < 0.3) and (1 - math.abs(alt - 0.05) / 0.25) or 0
    dusk = math.clamp(dusk, 0, 1) * 0.85
    -- 开飞机飞得越高大气越淡、雾越远（用户：飞机视野有点近）
    local cam = workspace.CurrentCamera
    local hk = (G.fly and cam) and smooth(150, 1800, cam.CFrame.Position.Y) or 0
    -- 夜视仪、热成像（G.nvLight），坦克瞄准镜、车里观瞄设备的夜视档（G.sightNv / G.opticNv：原来开着瞄准镜时夜视仪让出画面、增亮也跟着撤了，镜里的夜视档一片墨绿）
    local nv = G.nvLight == true or G.sightNv == true or G.opticNv == true
    local nk = 1 - dayK
    pcall(function()
      put(Lighting, "ClockTime", clock)
      put(Lighting, "Brightness", lerp(NIGHT.bright, DAY.bright, dayK))
      local amb, oamb = lc(NIGHT.amb, DAY.amb, dayK), lc(NIGHT.oamb, DAY.oamb, dayK)
      local exp = lerp(NIGHT.exp, DAY.exp, dayK)
      if nv then   -- 夜视：本地增亮（白天只亮一点点；沙漠少加，见 nvEv）
        exp += nvEv() * nk + 0.25 * dayK
        amb, oamb = lc(amb, RGB(52, 60, 56), nk), lc(oamb, RGB(96, 110, 100), nk)
      end
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
      put(Lighting, "ColorShift_Top", lc(lc(NIGHT.top, DAY.top, dayK), DUSK.top, dusk))
      put(Lighting, "ColorShift_Bottom", lc(NIGHT.bot, DAY.bot, dayK))
      put(Lighting, "EnvironmentDiffuseScale", lerp(NIGHT.diff, DAY.diff, dayK))
      put(Lighting, "EnvironmentSpecularScale", lerp(NIGHT.spec, DAY.spec, dayK))
      put(Lighting, "FogColor", lc(lc(NIGHT.fog, DAY.fog, dayK), DUSK.fog, dusk))
      local wk = G.weather and G.weather.k or 0   -- 暴风雨（Warfx.lua）：雾变近、大气变浑
      -- 老式的雾放到十万格（有 Atmosphere 时 Roblox 按大气算远处，这个基本不起作用；没有大气的时候也别挡）
      put(Lighting, "FogEnd", 100000 * (1 - 0.7 * wk))
      local atm = Lighting:FindFirstChildOfClass("Atmosphere")
      if atm then
        local dens = lerp(NIGHT.dens, DAY.dens, dayK) * (1 - 0.5 * hk)
        if nv then dens = math.max(0.035, dens * 0.6) end
        put(atm, "Density", dens + 0.12 * wk)
        put(atm, "Color", lc(lc(NIGHT.acol, DAY.acol, dayK), DUSK.acol, dusk))
        put(atm, "Decay", lc(lc(NIGHT.adec, DAY.adec, dayK), DUSK.adec, dusk))
        put(atm, "Glare", lerp(NIGHT.glare, DAY.glare, dayK) + 0.6 * dusk)
        put(atm, "Haze", lerp(NIGHT.haze, DAY.haze, dayK) * (1 - 0.5 * hk) + 1.2 * wk)
      end
      local bloom = Lighting:FindFirstChild("NightBloom")
      if bloom then
        put(bloom, "Intensity", lerp(NIGHT.bloomI, DAY.bloomI, dayK))
        put(bloom, "Threshold", lerp(NIGHT.bloomT, DAY.bloomT, dayK))
      end
      local cc = Lighting:FindFirstChild("NightGrade")
      if cc then
        put(cc, "Saturation", lerp(NIGHT.ccSat, DAY.ccSat, dayK))
        put(cc, "Contrast", lerp(NIGHT.ccCon, DAY.ccCon, dayK))
        put(cc, "TintColor", lc(NIGHT.ccTint, DAY.ccTint, dayK))
      end
    end)
  end
  G.stepDayNight = step
  step(1)

  -- 远处模糊（景深，用户 11-22：「视野给我改成无限远好了，然后远处模糊这样」）：近处清楚、越远越糊（Roblox 景深的对焦距离、清楚范围最多 200 + 50 格）；
  --   要看清远处的时候关掉：步兵开镜 / 举枪瞄准、望远镜、坦克瞄准镜、车里的观瞄设备、飞机光电吊舱、阵亡镜头（它自己有景深）；画面卡（自动画质低）也关
  local far = Instance.new("DepthOfFieldEffect")
  far.Name = "FarBlur"
  far.FocusDistance, far.InFocusRadius, far.NearIntensity, far.FarIntensity = 200, 50, 0, 0.2
  far.Parent = Lighting
  G.farBlur = far   -- 测试用
  G.frameConn("FarBlur", function()
    local dr, fl = G.drive, G.fly
    local sharp = G.scopeOn == true or G.fpsAiming == true or (dr ~= nil and (dr.sight or dr.eo)) or G.interiorOptic ~= nil
      or (fl ~= nil and fl.eo == true) or (G.killcamOn ~= nil and G.killcamOn()) or (G.perfK or 1) < 0.7
    local want = not sharp
    if far.Enabled ~= want then far.Enabled = want end
    if want then
      local k = fl and 0.1 or 0.2   -- 开飞机看的本来就是几公里外：糊得轻一点
      if math.abs(far.FarIntensity - k) > 0.005 then far.FarIntensity = k end
    end
  end)
end

return DayNight
