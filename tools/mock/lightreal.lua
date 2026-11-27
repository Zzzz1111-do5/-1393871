-- 光影（用户 11-27「光影照战雷做」：黄昏侧光暖、阴影软硬合适、远处空气透视、雪地反光不过曝、夜里月光冷；M3 上丝滑）：
--   python3 tools/mock/run.py tools/mock/lightreal.lua
--   不开整个服务器（一两分钟跑完）：装好 src，换图，直接跑 World.lighting（服务器）和 DayNight / SnowLook（客户端）
--   ① 各图各时段的数在规格（2026-11-27「特效和光影改法规格」第 5 节）的范围里，几个关键数和规格一样
--   ② 钟点一路走过去，混合出来的数是连续的（没有一下跳的）；正午是白天那套、半夜是夜里那套、日落前后是黄昏那套、日出前后是清晨那套
--   ③ 开服（World.lighting）按当前钟点设一套（不再写死夜里：开局白天时不闪一下夜里）；纬度、风、新版光照按图
--   ④ 客户端 DayNight：设到 Lighting 上的就是那一套；训练场那块换训练场那套；钟点跳了一秒左右缓过去；
--     白天稳定时一个属性都不重复写；太阳光束夜里关；远处景深只在开飞机时开
--   ⑤ 纬度自检：日出日落跟着纬度挪的算法退回 23 度、0 度；判断不了照用
--   ⑥ 雪山：下雪是圆点贴图（不是八角星）、受光、每秒不超过 400 片，机器跟不上少下
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check
T.scripts = dofile(MOCK_DIR .. "/load.lua")(R, SRC_DIR)
local RS = R.services.ReplicatedStorage
local L = R.services.Lighting
local V3, CF = R.Vector3.new, R.CFrame.new
local typeof = R.typeof

local LL = R.require(RS:FindFirstChild("LightLooks"))
local DC = R.require(RS:FindFirstChild("DayClock"))
local Map = R.require(RS:FindFirstChild("Map"))
local function rgb(c) return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end
local function cdiff(a, b) return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) end
local function near(a, b, eps)
  if type(a) == "number" then return math.abs(a - b) <= (eps or 1e-3) end
  return cdiff(a, b) <= (eps or 3e-3)
end
local function lum(c) return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B end

print("① 各图各时段的数")
local LOOKS = { "city", "sands", "snow", "range" }
local PH = { "day", "dusk", "dawn", "night" }
local missing = {}
for _, key in ipairs(LOOKS) do
  for _, ph in ipairs(PH) do
    local s = LL.LOOK[key] and LL.LOOK[key][ph]
    for _, k in ipairs(LL.KEYS) do
      local v = s and s[k]
      local isColor = (k == "amb" or k == "oamb" or k == "top" or k == "bot" or k == "acol" or k == "adec" or k == "ccTint")
      if v == nil or (isColor and typeof(v) ~= "Color3") or (not isColor and type(v) ~= "number") then missing[#missing + 1] = key .. "." .. ph .. "." .. k end
    end
  end
end
check(#missing == 0, "四张图 × 白天 / 黄昏 / 清晨 / 夜里，" .. #LL.KEYS .. " 个字段都齐、类型对（缺：" .. table.concat(missing, " ") .. "）")
-- 范围（规格 5.0 的道理）：{ 字段, 时段, 最小, 最大 }
local RANGES = {
  { "bright", "day", 2.8, 3.5 }, { "bright", "dusk", 2.0, 2.6 }, { "bright", "night", 1.8, 2.1 },
  { "exp", "day", -0.4, 0.05 }, { "exp", "night", 0.3, 0.5 },
  { "shadow", "day", 0.14, 0.2 }, { "shadow", "dusk", 0.2, 0.3 }, { "shadow", "night", 0.3, 0.42 },
  { "dens", "day", 0.12, 0.15 }, { "dens", "dusk", 0.16, 0.2 }, { "dens", "night", 0.1, 0.13 },
  { "off", "day", 0.1, 0.25 }, { "haze", "day", 0.6, 1.3 }, { "haze", "dusk", 1.5, 2.0 },
  { "glare", "day", 0.2, 0.5 }, { "glare", "dusk", 0.8, 1.0 }, { "glare", "night", 0, 0 },
  { "bloomT", "day", 1.2, 1.35 }, { "bloomT", "dusk", 1.0, 1.1 }, { "bloomT", "night", 0.9, 1.0 },
  { "bloomI", "day", 0.4, 0.6 }, { "bloomI", "night", 0.9, 1.2 },
  { "rays", "day", 0.03, 0.08 }, { "rays", "dusk", 0.12, 0.18 }, { "rays", "night", 0, 0 },
  { "diff", "day", 0.5, 0.95 }, { "diff", "night", 0.2, 0.35 }, { "spec", "day", 0.65, 1 },
  { "ccS", "night", -0.17, -0.09 }, { "ccC", "day", 0.08, 0.15 },
}
local bad = {}
for _, key in ipairs(LOOKS) do
  for _, r in ipairs(RANGES) do
    local v = LL.LOOK[key][r[2]][r[1]]
    if type(v) ~= "number" or v < r[3] - 1e-9 or v > r[4] + 1e-9 then bad[#bad + 1] = string.format("%s.%s.%s=%s", key, r[2], r[1], tostring(v)) end
  end
end
check(#bad == 0, "都在规格的范围里（亮度、曝光、阴影、大气、泛光门槛、光束……）" .. (#bad > 0 and ("：" .. table.concat(bad, " ")) or ""))
-- Glare 要 Haze > 0 才有效、Decay 要两个都 > 0：有 Glare 的都有 Haze
local gh = true
for _, key in ipairs(LOOKS) do for _, ph in ipairs(PH) do local s = LL.LOOK[key][ph] if s.glare > 0 and s.haze <= 0 then gh = false end end end
check(gh, "有太阳周围那圈光（Glare）的时段都有霾（Haze > 0，不然 Glare 不起作用）")
-- 规格里的几个关键数（照抄的，改了要同步规格）
local C, S, N = LL.LOOK.city, LL.LOOK.sands, LL.LOOK.snow
check(C.day.bright == 3.0 and rgb(C.day.oamb) == "86,92,104" and C.day.diff == 0.75 and C.day.dens == 0.14 and C.day.bloomT == 1.25 and C.day.shadow == 0.18,
  "钢城白天：亮度 3、天光 86,92,104、反光 0.75、大气 0.14、泛光门槛 1.25、阴影 0.18")
check(rgb(C.dusk.top) == "255,158,90" and C.dusk.glare == 0.95 and C.dusk.haze == 1.8 and rgb(C.dawn.top) == "255,190,150" and C.dawn.haze == 2.0 and C.dawn.ccS == 0.06,
  "钢城黄昏太阳 255,158,90、Glare 0.95 / Haze 1.8；清晨太阳 255,190,150、晨雾 Haze 2.0、饱和 0.06")
check(rgb(C.night.top) == "138,156,206" and C.night.exp == 0.45 and C.night.bright == 2.0, "钢城夜里月光 138,156,206、曝光 0.45、亮度 2")
check(S.day.dens == 0.14 and S.day.exp == -0.12 and rgb(S.day.bot) == "96,76,54", "沙海白天大气 0.14（一两公里对射，不再浓）、曝光 −0.12、沙地反光 96,76,54")
check(N.day.exp == -0.35 and N.day.off == 0.24 and rgb(N.day.bot) == "92,106,130" and N.day.bloomT == 1.2, "雪山白天曝光 −0.35、Offset 0.24（远山轮廓）、雪反光冷蓝 92,106,130、泛光门槛 1.2")
check(LL.LOOK.range.day.dens == 0.12 and LL.LOOK.range.day.haze == 0.7 and rgb(LL.LOOK.range.day.bot) == "52,46,38" and LL.LOOK.range.night == C.night,
  "训练场白天大气 0.12、霾 0.7、地面反光 52,46,38；夜里同钢城")
-- 写实：黄昏侧光暖、夜里月光冷、白天天光不算两份、雪地不过曝
local warm, cold, ambLow = true, true, true
for _, key in ipairs(LOOKS) do
  local P = LL.LOOK[key]
  for _, ph in ipairs({ "dusk", "dawn" }) do if not (P[ph].top.R >= 0.99 and P[ph].top.R - P[ph].top.B >= 0.3) then warm = false end end
  if not (P.night.top.B > P.night.top.R and P.night.ccTint.B >= P.night.ccTint.R) then cold = false end
  if not (lum(P.day.amb) < 0.16 and math.max(P.day.oamb.R, P.day.oamb.G, P.day.oamb.B) < 0.53) then ambLow = false end
end
check(warm, "黄昏、清晨的太阳是暖的（红满、蓝少一大截）")
check(cold, "夜里的月光、调色偏冷蓝")
check(ambLow, "白天 Ambient 低、OutdoorAmbient 不超过 135（天光不算两份：背光面、车底暗下来）")
check(N.day.exp <= -0.3 and N.day.exp < C.day.exp and N.day.bloomT >= 1.2, "雪地白天曝光压得比钢城低、泛光门槛不低于 1.2（雪反光不过曝）")
check(rgb(N.day.bot) ~= rgb(C.day.bot) and N.day.bot.B > N.day.bot.R and S.day.bot.R > S.day.bot.B, "雪地反光冷蓝、沙地反光暖")
check(LL.LAT.city == 48 and LL.LAT.sands == 29 and LL.LAT.snow == 58 and LL.LAT.range == 40 and LL.LAT0 == 23, "纬度：钢城 48、沙海 29、雪山 58、训练场 40（原来 23）")
check(LL.WIND.city == V3(5, 0, 2) and LL.WIND.sands == V3(9, 0, 3) and LL.WIND.snow == V3(11, 0, -5) and LL.WIND.range == V3(4, 0, 2), "全局风：钢城 (5,0,2)、沙海 (9,0,3)、雪山 (11,0,−5)、训练场 (4,0,2)")

print("② 钟点一路走过去：连续、各时段到位")
local NUMK, COLK = {}, {}
for _, k in ipairs(LL.KEYS) do
  local v = LL.LOOK.city.day[k]
  if type(v) == "number" then NUMK[#NUMK + 1] = k else COLK[#COLK + 1] = k end
end
for _, key in ipairs(LOOKS) do
  local P = LL.LOOK[key]
  local span = {}
  for _, k in ipairs(NUMK) do
    local lo, hi = math.huge, -math.huge
    for _, ph in ipairs(PH) do lo, hi = math.min(lo, P[ph][k]), math.max(hi, P[ph][k]) end
    span[k] = hi - lo
  end
  local prev, worst, worstK, worstC = nil, 0, "", 0
  for i = 0, 4800 do   -- 每 0.005 小时（黄昏时现实里半秒）
    local c = (i * 0.005) % 24
    local v = LL.at(key, LL.weights(c, DC))
    if prev then
      for _, k in ipairs(NUMK) do
        local d = span[k] > 0 and math.abs(v[k] - prev[k]) / span[k] or 0
        if d > worst then worst, worstK, worstC = d, k, c end
      end
      for _, k in ipairs(COLK) do
        local d = cdiff(v[k], prev[k]) / 3
        if d > worst then worst, worstK, worstC = d, k, c end
      end
    end
    prev = v
  end
  check(worst < 0.03, string.format("%s：钟点每走 0.005 小时，每个数最多变它全程的 %.1f%%（%s，%.2f 点；一下跳的会过 3%%）", key, worst * 100, worstK, worstC))
  -- 正午 = 白天那套、半夜 = 夜里那套
  local noon, mid = LL.at(key, LL.weights(12, DC)), LL.at(key, LL.weights(0.5, DC))
  local okN, okM = true, true
  for _, k in ipairs(LL.KEYS) do
    if not near(noon[k], P.day[k]) then okN = false end
    if not near(mid[k], P.night[k]) then okM = false end
  end
  check(okN and okM, key .. "：正午就是白天那套、半夜就是夜里那套")
  -- 日落前后（17:48，太阳高度 0.05）黄昏占八成以上；日出后（6:12）用的是清晨那份
  local dk, tw = LL.weights(17.8, DC)
  local dusk = LL.at(key, LL.weights(17.8, DC))
  local dawn = LL.at(key, LL.weights(6.2, DC))
  check(tw >= 0.8 and cdiff(dusk.top, P.dusk.top) < cdiff(dusk.top, P.day.top) and math.abs(dusk.glare - P.dusk.glare) < 0.25,
    string.format("%s：17:48 黄昏权重 %.2f，太阳 %s（黄昏那份 %s）、Glare %.2f", key, tw, rgb(dusk.top), rgb(P.dusk.top), dusk.glare))
  check(cdiff(dawn.acol, P.dawn.acol) < cdiff(dawn.acol, P.dusk.acol), string.format("%s：6:12 天色是清晨那份（%s，清晨 %s / 黄昏 %s）", key, rgb(dawn.acol), rgb(P.dawn.acol), rgb(P.dusk.acol)))
end
-- 日落以后太阳没了：太阳的颜色不再是黄昏的橙色（月亮从东边升起来照成橙色就不对了）
do
  local after = LL.at("city", LL.weights(18.45, DC))
  local _, tw = LL.weights(18.45, DC)
  check(tw > 0.2 and after.top.B > after.top.R * 0.85, string.format("18:27 天边还有晚霞（黄昏权重 %.2f），照下来的光已经是月光的颜色（%s）", tw, rgb(after.top)))
end

print("③ 开服：World.lighting 按当前钟点设一套、纬度、风、新版光照")
local World = R.require(R.services.ServerScriptService:FindFirstChild("Main"):FindFirstChild("World"))
local function serverAt(mapId, c)
  Map.use(mapId)
  R.workspace:SetAttribute("DayFix", c)
  World.lighting()
  local atm = L:FindFirstChildOfClass("Atmosphere")
  local key = LL.keyFor(Map, nil)
  local v = LL.at(key, LL.weights(c, DC))
  return v, atm, key
end
for _, m in ipairs({ { "city", "city" }, { "sands", "sands" }, { "snow", "snow" } }) do
  local v, atm, key = serverAt(m[1], 9.5)
  check(key == m[2] and near(L.Brightness, v.bright) and near(L.OutdoorAmbient, v.oamb) and near(L.ShadowSoftness, v.shadow) and atm and near(atm.Density, v.dens) and near(atm.Offset, v.off),
    string.format("%s 上午 9:30 开服：亮度 %.2f、天光 %s、阴影 %.2f、大气 %.3f / Offset %.2f（和客户端那套一样）", m[1], L.Brightness, rgb(L.OutdoorAmbient), L.ShadowSoftness, atm and atm.Density or -1, atm and atm.Offset or -1))
  check(L.GeographicLatitude == LL.LAT[key] and R.workspace.GlobalWind == LL.WIND[key], string.format("  纬度 %s、风 %s", tostring(L.GeographicLatitude), tostring(R.workspace.GlobalWind)))
end
check(L.LightingStyle == R.Enum.LightingStyle.Realistic and L.PrioritizeLightingQuality == true, "新版光照：LightingStyle = Realistic、PrioritizeLightingQuality")
check(math.abs(L.ClockTime - 9.5) < 0.011, "开服的钟点就是当前钟点（" .. tostring(L.ClockTime) .. "；原来写死半夜 2.3，开局白天时先闪一下夜里）")
local vn = serverAt("city", 2.3)
check(near(L.Brightness, vn.bright) and near(L.ColorShift_Top, LL.LOOK.city.night.top), "夜里开服就是夜里那套（月光 " .. rgb(L.ColorShift_Top) .. "）")
local bl, cc = L:FindFirstChild("NightBloom"), L:FindFirstChild("NightGrade")
check(bl and cc and L:FindFirstChildOfClass("Sky") ~= nil and near(bl.Threshold, vn.bloomT) and near(cc.Saturation, vn.ccS), "泛光、调色、天空都建了")

print("④ 客户端 DayNight")
local frames = {}
local hooks = {}
local CG = { Map = Map, perfFixed = true }
CG.frameConn = function(name, f) frames[name] = f end
CG.onMap = function(f) hooks[#hooks + 1] = f end
local Client = R.services.StarterPlayer:FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
Map.use("city")
R.workspace:SetAttribute("DayFix", 12)
R.require(Client:FindFirstChild("DayNight")).init(CG)
local cam = R.workspace.CurrentCamera
cam.CFrame = CF(0, 40, 0)
local function tick(sec)
  for _ = 1, math.max(1, math.floor(sec / 0.1 + 0.5)) do
    CG.stepDayNight(0.1)
    if frames.FarBlur then frames.FarBlur(0.1) end
  end
end
tick(1)
local atm = L:FindFirstChildOfClass("Atmosphere")
local rays, far = L:FindFirstChild("SunShafts"), L:FindFirstChild("FarBlur")
local function matches(v, what)
  local okAll = near(L.Brightness, v.bright) and near(L.Ambient, v.amb) and near(L.OutdoorAmbient, v.oamb) and near(L.ColorShift_Top, v.top)
    and near(L.ColorShift_Bottom, v.bot) and near(L.EnvironmentDiffuseScale, v.diff) and near(L.EnvironmentSpecularScale, v.spec)
    and near(L.ExposureCompensation, v.exp) and near(L.ShadowSoftness, v.shadow) and near(atm.Density, v.dens) and near(atm.Offset, v.off)
    and near(atm.Color, v.acol) and near(atm.Decay, v.adec) and near(atm.Glare, v.glare) and near(atm.Haze, v.haze)
    and near(bl.Intensity, v.bloomI) and near(bl.Size, v.bloomS, 0.01) and near(bl.Threshold, v.bloomT) and near(cc.Brightness, v.ccB)
    and near(cc.Contrast, v.ccC) and near(cc.Saturation, v.ccS) and near(cc.TintColor, v.ccTint)
  check(okAll, what .. string.format("（亮度 %.2f、曝光 %.2f、阴影 %.2f、大气 %.3f、泛光 %.2f / %.2f）", L.Brightness, L.ExposureCompensation, L.ShadowSoftness, atm.Density, bl.Intensity, bl.Threshold))
end
matches(LL.LOOK.city.day, "钢城正午：Lighting、大气、泛光、调色全是白天那套")
local look = CG.lightLook()
check(look.key == "city" and L.GeographicLatitude == 48 and R.workspace.GlobalWind == V3(5, 0, 2), "纬度 48、风 (5,0,2)（模拟器没有太阳方向：判断不了照用）")
check(rays and rays.Enabled and near(rays.Intensity, LL.LOOK.city.day.rays) and far and not far.Enabled, string.format("白天太阳光束开着（%.3f）；地面上远处景深关着", rays and rays.Intensity or -1))
-- 稳定时不重复写（灯光属性写一次就要重算：原来 11-18「一卡一卡的」）
R.ops = {}
tick(3)
local writes = 0
for k, n in pairs(R.ops) do if k:find("\tset ", 1, true) then writes = writes + n end end
R.ops = nil
check(writes == 0, "白天稳定时三秒钟一个灯光属性都没重写（写了 " .. writes .. " 次）")
-- 夜里：月光、太阳光束关
R.workspace:SetAttribute("DayFix", 1.5)
tick(7)
matches(LL.LOOK.city.night, "拨到半夜 1:30（缓过去以后）：全是夜里那套")
check(not rays.Enabled and not far.Enabled, "夜里太阳光束关掉（省一遍后期）")
-- 钟点跳了：缓过去，不一下跳
R.workspace:SetAttribute("DayFix", 12)
local b0 = L.Brightness
tick(0.1)
local b1 = L.Brightness
tick(0.9)
local b2 = L.Brightness
tick(6)
local span = LL.LOOK.city.day.bright - LL.LOOK.city.night.bright
check(b1 - b0 > 0 and b1 - b0 < 0.25 * span and b2 - b0 > 0.55 * span and near(L.Brightness, LL.LOOK.city.day.bright),
  string.format("从半夜跳到正午（每局开局拨回早上那种）：亮度 %.2f → 0.1 秒 %.2f → 1 秒 %.2f → %.2f，缓过去不一下跳", b0, b1, b2, L.Brightness))
-- 黄昏：暖侧光、阴影软一点、光束最明显
R.workspace:SetAttribute("DayFix", 17.8)
tick(7)
local cd = LL.at("city", LL.weights(17.8, DC))
check(near(L.ColorShift_Top, cd.top) and L.ColorShift_Top.R > 1.6 * L.ColorShift_Top.B and L.ShadowSoftness > LL.LOOK.city.day.shadow and rays.Enabled and rays.Intensity > LL.LOOK.city.day.rays,
  string.format("17:48 黄昏：太阳 %s、阴影 %.2f、光束 %.3f", rgb(L.ColorShift_Top), L.ShadowSoftness, rays.Intensity))
-- 钟点照常走过日落（快进：每次更新算现实 6 秒）：每次更新最多写二十几个属性，亮度一步步变
R.osTime = 1.8e9   -- 服务器时钟（GetServerTimeNow）由测试推
R.workspace:SetAttribute("DayFix", 17.0)
tick(7)   -- 先停在 17:00 缓到位，下面量的是钟点自己走的那一段
R.workspace:SetAttribute("DayFix", nil)
R.workspace:SetAttribute("DayT0", DC.t0For(17.0, R.workspace:GetServerTimeNow()))
R.ops = {}
local stepsN, maxStep, prevB = 40, 0, nil
for _ = 1, stepsN do
  R.osTime = R.osTime + 6
  CG.stepDayNight(6)
  if prevB then maxStep = math.max(maxStep, math.abs(L.Brightness - prevB)) end
  prevB = L.Brightness
end
local tw = 0
for k, n in pairs(R.ops) do if k:find("\tset ", 1, true) then tw = tw + n end end
R.ops = nil
local cEnd = CG.clockNow()
check(cEnd > 18.5 and tw <= stepsN * 28 and tw >= stepsN * 5 and maxStep < 0.12,
  string.format("17:00 走到 %.2f（快进 4 分钟）：%d 次更新共写 %d 个属性（每次最多二十几个），亮度每步最多变 %.3f", cEnd, stepsN, tw, maxStep))
R.osTime = nil
-- 开飞机才开远处景深；看光电吊舱时关
R.workspace:SetAttribute("DayFix", 12)
tick(7)
CG.fly = {}
tick(0.2)
check(far.Enabled and near(far.FarIntensity, 0.035), "开飞机：远处景深开（很轻，0.035）")
CG.fly.eo = true
tick(0.2)
check(not far.Enabled, "看光电吊舱：景深关")
CG.fly = nil
tick(0.2)
check(not far.Enabled, "下了飞机：景深关")
local effects = 0
for _, e in ipairs(L:GetChildren()) do if e:IsA("PostEffect") and e.Enabled then effects = effects + 1 end end
check(effects <= 3, "地面上白天开着的后期效果 " .. effects .. " 个（泛光、调色、太阳光束）")
-- 夜视、照明弹、开飞机高度照旧叠在上面
CG.nvLight = true
R.workspace:SetAttribute("DayFix", 1.5)
tick(7)
check(L.ExposureCompensation > LL.LOOK.city.night.exp + 2 and atm.Density < LL.LOOK.city.night.dens, string.format("夜里开夜视：曝光 %.2f、大气 %.3f（照旧增亮、看得远一点）", L.ExposureCompensation, atm.Density))
CG.nvLight = nil
-- 训练场那块：训练场那套（白天大气淡一点）、纬度 40、风 (4,0,2)
R.workspace:SetAttribute("DayFix", 12)
cam.CFrame = CF(0, 40, 100352)
tick(0.2)
look = CG.lightLook()
check(look.key == "range" and near(atm.Density, LL.LOOK.range.day.dens) and L.GeographicLatitude == 40 and R.workspace.GlobalWind == V3(4, 0, 2),
  string.format("镜头到训练场：用训练场那套（大气 %.3f）、纬度 %s、风 %s", atm.Density, tostring(L.GeographicLatitude), tostring(R.workspace.GlobalWind)))
cam.CFrame = CF(0, 40, 0)
-- 换图：沙海、雪山
for _, m in ipairs({ "sands", "snow" }) do
  Map.use(m)
  for _, f in ipairs(hooks) do f(m) end
  tick(0.3)
  look = CG.lightLook()
  matches(LL.LOOK[m].day, m .. " 正午：全是这张图白天那套")
  check(look.key == m and L.GeographicLatitude == LL.LAT[m] and R.workspace.GlobalWind == LL.WIND[m], string.format("  纬度 %s、风 %s", tostring(L.GeographicLatitude), tostring(R.workspace.GlobalWind)))
end
R.workspace:SetAttribute("DayFix", 23)
tick(7)
check(near(L.ColorShift_Top, LL.LOOK.snow.night.top) and L.ColorShift_Top.B > L.ColorShift_Top.R and L.ExposureCompensation >= 0.4,
  string.format("雪山夜里：月光照雪 %s、曝光 %.2f", rgb(L.ColorShift_Top), L.ExposureCompensation))

print("⑤ 纬度自检")
local function ew(c, lat)   -- 太阳沿着过正东、正西的大圆走（6 点日出 18 点日落），纬度只让它往南倾
  return math.sin((c - 6) / 12 * math.pi) * math.cos(math.rad(lat - 23.5))
end
local function seasonal(c, lat)   -- 按季节算（夏至）：高纬度日出早、日落晚
  local d, phi, h = math.rad(23.44), math.rad(lat), math.rad((c - 12) * 15)
  return math.sin(phi) * math.sin(d) + math.cos(phi) * math.cos(d) * math.cos(h)
end
local function stale() return 0.42 end
check(CG.dnLatPick(48, ew) == 48 and CG.dnLatPick(58, ew) == 58, "太阳 6 点升 18 点落的算法：纬度照用（48、58）")
check(CG.dnLatPick(48, seasonal) == 0, "按季节走的算法（48 度 6 点太阳已经 17° 高）：23 度也不行，退到 0 度（赤道一年都是 6 点日出）")
check(CG.dnLatPick(58, stale) == 58, "太阳没跟着钟点动（读到旧值）：判断不了，照用")
check(L.GeographicLatitude == LL.LAT.snow, "试纬度不改动画面上的纬度（拨回来了：" .. tostring(L.GeographicLatitude) .. "）")

print("⑥ 雪山：下雪")
CG.perfK = 1
R.require(Client:FindFirstChild("SnowLook")).init(CG)
local board = R.workspace:FindFirstChild("SnowFall")
local pe = board and board:FindFirstChildOfClass("ParticleEmitter")
local smax = 0
if pe then for _, kp in ipairs(pe.Size.Keypoints) do smax = math.max(smax, kp.Value + kp.Envelope) end end
check(pe ~= nil and pe.Texture:find("explosion01_implosion_main", 1, true) ~= nil and pe.LightInfluence == 1 and pe.Rate <= 400 and smax <= 0.3,
  string.format("雪花是柔边圆点（%s）、受光、每秒 %s 片（引擎上限 400）、最大 %.2f 格", pe and pe.Texture or "没有", tostring(pe and pe.Rate), smax))
local acc = pe and pe.Acceleration
local wsn = LL.WIND.snow
check(acc and math.abs(acc.X * wsn.Z - acc.Z * wsn.X) < 1e-3 and acc.X * wsn.X > 0 and math.abs(math.sqrt(acc.X ^ 2 + acc.Z ^ 2) - 2.77) < 0.01,
  "雪顺着雪山的全局风斜着飘（" .. tostring(acc) .. "，风 " .. tostring(wsn) .. "）")
CG.perfK = 0.6
if frames.snowlook then for _ = 1, 8 do frames.snowlook(0.1) end end
check(pe and pe.Rate < 300 and pe.Rate >= 200, "机器跟不上（自动画质 0.6）：雪下得稀一点（" .. tostring(pe and pe.Rate) .. " 片）")
CG.perfK = 1
if frames.snowlook then for _ = 1, 8 do frames.snowlook(0.1) end end
check(pe and pe.Rate == 400, "画质回来：400 片")

print("⑦ 没有报错")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
