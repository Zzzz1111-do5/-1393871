-- Roblox全面大战场（客户端）——昼夜更替（用户：改成昼夜更替吧，一直黑天玩起来有点怪；11-18 又说把白天模式去掉、锁定晚上：Config.DayNight.lockNight；
--   11-25：「给沙漠地图做个昼夜更替」——又打开了）
--   钟点在 ReplicatedStorage/DayClock.lua（服务器、客户端同一套：照明弹只在夜里打也看它）：一圈 32 分钟——白天 7:00～17:00 十四分钟、
--   黄昏三分钟、夜里 19:30～4:30 十二分钟、清晨三分钟；跨局接着走；PvE 关卡按自己的钟点开局（夜战关卡钉在夜里）
--   跟着太阳高度渐变：亮度、环境光、天空光的颜色（黄昏偏橙）、雾、大气（白天通透、看得远）、泛光和调色（夜里冷蓝、白天中性）；
--   开飞机飞得越高大气越淡（用户：飞机视野有点近）。夜视仪（Night.lua）开着时在这上面加亮、变绿，白天开夜视只亮一点点
--   G.dayK()：0 夜里 ～ 1 白天；G.isNight()：天黑了（出生自动开夜视看这个）
local Lighting = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")

local DayNight = {}

function DayNight.init(G)
  local Config = require(RS:WaitForChild("Config"))
  local DC = require(RS:WaitForChild("DayClock"))
  local RGB = Color3.fromRGB
  local function lerp(a, b, t) return a + (b - a) * t end
  local function lc(a, b, t) return a:Lerp(b, t) end
  local function smooth(a, b, v) local t = math.clamp((v - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end


  -- 夜里 / 白天两套（夜里照 World.lighting 原来那套）
  -- 大气（用户 11-22：「视野给我改成无限远好了，然后远处模糊这样」）：原来夜里 0.21、白天 0.17，几公里外就灰成一片；
  --   放淡到 0.085 / 0.07、霾减半，远处的山、岛、舰队看得见，远处的「看不清」改成下面的景深模糊（FarBlur）
  -- 用户 11-25「目前整个画质都一般 提高一下」「光效」：白天原来环境光、天光太亮（暗处 132 灰），阳光照的一面和背光的一面差不多亮，
  --   影子又虚（ShadowSoftness 0.3），整个画面平、发灰。改成：太阳更强、天光压低（背光面、车底、影子里暗下来，立体感出来），
  --   影子收紧（白天 0.12：车、房子、石头的影子边缘清楚）；泛光门槛降低（爆炸、曳光、炮口焰、太阳照到的金属白天也泛光），
  --   调色对比、饱和略加、暖一点；太阳光束（SunRays：对着太阳看时从云边、车边透出来的光，黄昏最明显）
  local NIGHT = { bright = 2.2, amb = RGB(14, 17, 24), oamb = RGB(38, 45, 62), top = RGB(140, 160, 210), bot = RGB(8, 10, 16), diff = 0.35, spec = 0.9, exp = 0.55,
    fog = RGB(16, 20, 30), dens = 0.085, acol = RGB(44, 54, 76), adec = RGB(12, 15, 24), glare = 0.15, haze = 0.5,
    bloomI = 1.1, bloomT = 1.05, bloomS = 36, ccSat = -0.12, ccCon = 0.14, ccTint = RGB(222, 232, 255), shadow = 0.3, rays = 0 }
  local DAY = { bright = 3.3, amb = RGB(56, 58, 64), oamb = RGB(104, 108, 116), top = RGB(255, 246, 230), bot = RGB(42, 38, 32), diff = 1, spec = 1, exp = 0.05,
    fog = RGB(176, 194, 214), dens = 0.07, acol = RGB(196, 208, 224), adec = RGB(96, 112, 136), glare = 0.35, haze = 0.3,
    bloomI = 0.6, bloomT = 1.3, bloomS = 26, ccSat = 0.08, ccCon = 0.12, ccTint = RGB(255, 251, 244), shadow = 0.12, rays = 0.055 }
  -- 夜视增亮多少档曝光（用户 11-22：「夜视仪视角沙漠的地面全是白色的」）：海岛的地面是草（亮度约 0.23），沙漠全是沙（约 0.5，亮一倍多），
  --   同样 +2.7 档沙地直接过曝成一片白（车里的昼光观瞄镜里就是一片黄）；沙漠少加 1.2 档，沙地落在跟海岛草地差不多的亮度
  local Map = require(RS:WaitForChild("Map"))
  local function isDesert() return Map.DESERT end   -- 沙海（MapSands）
  local function nvEv() return isDesert() and 1.5 or 2.7 end
  local DUSK = { top = RGB(255, 162, 98), fog = RGB(212, 146, 110), acol = RGB(236, 154, 104), adec = RGB(166, 74, 46) }
  local DAWN = { top = RGB(255, 196, 160), fog = RGB(196, 164, 156), acol = RGB(218, 176, 160), adec = RGB(122, 86, 84) }   -- 清晨：偏粉、淡一点
  -- 沙漠图：夜里的天光、雾偏暖褐（沙尘），白天是发白的黄沙天、看得没那么远。地图是开服后第一个玩家选的：进服时还没定、
  --   选了沙漠才换过来（init.client.lua 的 G.onMap），所以这里换地图时再套一次（服务器一局里不会从沙漠换回海岛，套一次就够）
  local desertSet = false
  local function desertPalette()
    if desertSet or not isDesert() then return end
    desertSet = true
    NIGHT.fog, NIGHT.acol, NIGHT.adec, NIGHT.oamb = RGB(26, 22, 20), RGB(70, 60, 54), RGB(22, 17, 14), RGB(50, 46, 48)
    NIGHT.ccTint = RGB(240, 234, 236)
    -- 沙海白天（用户 11-25 昼夜更替）：原来这套是给删掉的「沙漠风暴」调的（大气 0.22、霾 1.4，几公里外就黄成一片）；
    --   沙海坦克一两公里对射、飞机十几公里外交战：淡一点的暖黄沙尘霾，太阳刺眼一点，沙地反光把暗处抬暖
    DAY.fog, DAY.acol, DAY.adec, DAY.dens, DAY.haze = RGB(214, 198, 172), RGB(226, 212, 186), RGB(170, 138, 104), 0.11, 0.9
    DAY.glare, DAY.amb, DAY.oamb, DAY.bot = 0.45, RGB(66, 60, 54), RGB(120, 112, 100), RGB(64, 50, 34)   -- 沙地反光把暗处抬暖一点（比原来暗：影子要看得出来）
    DAY.top, DAY.exp = RGB(255, 242, 218), -0.05
    DAY.ccTint, DAY.ccSat = RGB(255, 246, 232), 0.05
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
    clock = DC.clock()   -- 锁定晚上（lockNight）、PvE 钉住的钟点（DayFix）、跨局走的（DayT0）都在 DayClock 里
    local alt = DC.sunAlt(clock)   -- 太阳高度（−1 半夜 ～ 1 正午）
    dayK = DC.dayK(clock)
    local tw = (clock < 12) and DAWN or DUSK   -- 地平线上那一段：上午是清晨的颜色，下午是黄昏的
    local dusk = (alt > -0.18 and alt < 0.3) and (1 - math.abs(alt - 0.05) / 0.25) or 0
    dusk = math.clamp(dusk, 0, 1) * 0.85
    -- 开飞机飞得越高大气越淡、雾越远（用户：飞机视野有点近）
    local cam = workspace.CurrentCamera
    local hk = (G.fly and cam) and smooth(150, 1800, cam.CFrame.Position.Y) or 0
    -- 夜视仪、热成像（G.nvLight），坦克瞄准镜、车里观瞄设备的夜视档（G.sightNv / G.opticNv：原来开着瞄准镜时夜视仪让出画面、增亮也跟着撤了，镜里的夜视档一片墨绿）
    local nv = G.nvLight == true or G.sightNv == true or G.opticNv == true
    local nk = 1 - dayK
    pcall(function()
      -- 太阳 / 月亮的位置分步挪：每格 0.02 小时（游戏里 1.2 分钟，现实里一两秒一格，影子挪 0.3°，看不出跳）——
      --   太阳一动整张阴影图都要重算，原来每 0.1 秒挪一下（用户 11-18「一卡一卡的」；11-25「特别卡」）
      put(Lighting, "ClockTime", math.floor(clock / 0.02 + 0.5) * 0.02)
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
      put(Lighting, "ColorShift_Top", lc(lc(NIGHT.top, DAY.top, dayK), tw.top, dusk))
      put(Lighting, "ColorShift_Bottom", lc(NIGHT.bot, DAY.bot, dayK))
      put(Lighting, "EnvironmentDiffuseScale", lerp(NIGHT.diff, DAY.diff, dayK))
      put(Lighting, "EnvironmentSpecularScale", lerp(NIGHT.spec, DAY.spec, dayK))
      put(Lighting, "FogColor", lc(lc(NIGHT.fog, DAY.fog, dayK), tw.fog, dusk))
      local wk = G.weather and G.weather.k or 0   -- 暴风雨（Warfx.lua）：雾变近、大气变浑
      -- 老式的雾放到十万格（有 Atmosphere 时 Roblox 按大气算远处，这个基本不起作用；没有大气的时候也别挡）
      put(Lighting, "FogEnd", 100000 * (1 - 0.7 * wk))
      local atm = Lighting:FindFirstChildOfClass("Atmosphere")
      if atm then
        local dens = lerp(NIGHT.dens, DAY.dens, dayK) * (1 - 0.5 * hk)
        if nv then dens = math.max(0.035, dens * 0.6) end
        put(atm, "Density", dens + 0.12 * wk)
        put(atm, "Color", lc(lc(NIGHT.acol, DAY.acol, dayK), tw.acol, dusk))
        put(atm, "Decay", lc(lc(NIGHT.adec, DAY.adec, dayK), tw.adec, dusk))
        put(atm, "Glare", lerp(NIGHT.glare, DAY.glare, dayK) + 0.6 * dusk)
        put(atm, "Haze", lerp(NIGHT.haze, DAY.haze, dayK) * (1 - 0.5 * hk) + 1.2 * wk)
      end
      local bloom = Lighting:FindFirstChild("NightBloom")
      if bloom then
        put(bloom, "Intensity", lerp(NIGHT.bloomI, DAY.bloomI, dayK))
        put(bloom, "Threshold", lerp(NIGHT.bloomT, DAY.bloomT, dayK))
        put(bloom, "Size", lerp(NIGHT.bloomS, DAY.bloomS, dayK))
      end
      local cc = Lighting:FindFirstChild("NightGrade")
      if cc then
        put(cc, "Saturation", lerp(NIGHT.ccSat, DAY.ccSat, dayK) + 0.06 * dusk)   -- 黄昏、清晨：颜色浓一点（金色的那一阵）
        put(cc, "Contrast", lerp(NIGHT.ccCon, DAY.ccCon, dayK))
        put(cc, "TintColor", lc(NIGHT.ccTint, DAY.ccTint, dayK))
      end
      -- 影子：白天收紧、夜里（月光、灯光）软一点；太阳光束：太阳在天上才有，黄昏、清晨太阳低的时候最明显
      put(Lighting, "ShadowSoftness", lerp(NIGHT.shadow, DAY.shadow, dayK))
      local rays = Lighting:FindFirstChild("SunShafts")
      if rays then
        put(rays, "Intensity", (lerp(NIGHT.rays, DAY.rays, dayK) + 0.09 * dusk) * (nv and 0.3 or 1))
        put(rays, "Spread", 0.55 + 0.3 * dusk)
      end
    end)
  end
  -- 太阳光束（客户端自己的后期效果：每个人本地加，服务器的 Lighting 里没有）
  pcall(function()
    if not Lighting:FindFirstChild("SunShafts") then
      local r = Instance.new("SunRaysEffect")
      r.Name = "SunShafts"
      r.Intensity, r.Spread = 0, 0.6
      r.Parent = Lighting
    end
  end)
  G.stepDayNight = step
  step(1)

  -- 远处模糊（景深，用户 11-22：「视野给我改成无限远好了，然后远处模糊这样」）：近处清楚、越远越糊（Roblox 景深的对焦距离、清楚范围最多 200 + 50 格）；
  --   要看清远处的时候关掉：步兵开镜 / 举枪瞄准、望远镜、坦克瞄准镜、车里的观瞄设备、飞机光电吊舱、阵亡镜头（它自己有景深）；画面卡（自动画质低）也关
  local far = Instance.new("DepthOfFieldEffect")
  far.Name = "FarBlur"
  -- 用户 11-25「画质一般」：原来远处糊 0.2——两百五十格（九十米）以外整片发糊，一两公里外的坦克、房子、山都是一团，画面看着「低清」；
  --   压到 0.06（只把很远的地平线柔一点，远近的层次靠大气），开飞机 0.03
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
      local k = fl and 0.03 or 0.06   -- 开飞机看的本来就是几公里外：糊得更轻
      if math.abs(far.FarIntensity - k) > 0.005 then far.FarIntensity = k end
    end
  end)
end

return DayNight
