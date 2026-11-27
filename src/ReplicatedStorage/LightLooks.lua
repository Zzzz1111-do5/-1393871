-- 全面大战场——各张图白天 / 黄昏 / 清晨 / 夜里的光照（服务器、客户端共用一份数）
--   用户 11-27：光影照战雷（Eagle's Shadow 那版）做——黄昏侧光暖、阴影软硬合适、远处有空气透视、雪地反光不过曝、夜里月光冷；
--   要在 Apple M3 上丝滑（后期效果只在用得上的时候开，见 DayNight.lua）。数照调研给的规格（2026-11-27「坦克对战：特效和光影改法规格」第 5 节）：
--   · 钢城（训练场、岛图照它）、沙海、雪山各一套，训练场白天大气淡一点；每套 day / dusk / dawn / night 四份，所有字段都参与混合：
--     先按 dayK（DayClock：0 夜里 ～ 1 白天）在 night、day 之间插，再按黄昏权重（twW，日落前后那一段）往 dusk（下午）/ dawn（上午）插
--   · 为什么这么调（规格 5.0）：
--     - 太阳硬、天光冷、Ambient 低：原来白天 OutdoorAmbient 104 加 EnvironmentDiffuseScale 1，天光算了两份，背光面、车底不够暗，画面平
--       （官方文档：调高 EnvironmentDiffuseScale 时要相应调低 Ambient、OutdoorAmbient）
--     - 大气：用户 11-22「视野给我改成无限远好了」压到 0.07～0.085（原来 0.17～0.21 几公里外就灰成一片）——这是用户要过的，不能悄悄推翻：
--       规格建议的白天 0.14～0.15、黄昏 0.18～0.19、霾 1.7～2.0（浓一倍）审查时退回来了：白天 0.07～0.09、黄昏 0.1、夜里照原来 0.085；
--       霾 Haze 白天不超过 0.8、黄昏 / 清晨不超过 1.2（沙海一两公里对射、黄昏开镜要看得清）。远处一层层淡下去（空气透视）就靠这点大气 +
--       地面上的远处景深（FarBlur 0.06，用户 11-22「远处模糊这样」、11-25 压淡，DayNight.lua）；Offset 留住远处的轮廓（雪山 0.24：远山的山脊线不糊进天里）。
--       颜色、Decay、Glare 照规格（各图一套）。tools/mock/lightreal.lua 查着：每张图白天 Density ≤ 0.1
--     - Glare 要 Haze > 0 才有效，Decay 要 Haze、Glare 都 > 0（夜里 Glare 0：Decay 不起作用，照样写一份免得插值跳）
--     - 泛光门槛白天不低于 1.2：只让亮度推过 2 的火球、闪光起光晕（太阳照着的墙、雪地不泛白）
--     - 阴影白天 0.14～0.18：战雷新阴影边缘平滑不抖，原来 0.12 太硬、会闪；黄昏 0.22～0.26、夜里 0.35～0.4（月光、灯光软）
--     - 曝光 +1 是两倍；雪地白天 −0.35（雪反照率 0.8 以上：压一档多才不过曝），夜里 +0.35～0.45
--   · 清晨（dawn）：规格只给了钢城（用黄昏那套，Top、大气颜色偏粉、Glare 0.7、Haze 2.0 晨雾、饱和 0.06）；沙海、雪山照同样的改法推的
--   · 纬度 LAT、全局风 WIND：服务器 World.lighting 按战场设，客户端 DayNight 按镜头在哪块（训练场 / 战场）再设一遍
local RGB = Color3.fromRGB

local L = {}

-- 参与混合的字段（DayNight 每次更新都按这张表插值）
L.KEYS = { "bright", "amb", "oamb", "top", "bot", "diff", "spec", "exp", "shadow", "dens", "off", "acol", "adec", "glare", "haze",
  "bloomI", "bloomS", "bloomT", "rays", "raysSpread", "ccB", "ccC", "ccS", "ccTint" }
-- 字段 → 设到哪（文档、测试用）
L.PROP = { bright = "Lighting.Brightness", amb = "Lighting.Ambient", oamb = "Lighting.OutdoorAmbient", top = "Lighting.ColorShift_Top",
  bot = "Lighting.ColorShift_Bottom", diff = "Lighting.EnvironmentDiffuseScale", spec = "Lighting.EnvironmentSpecularScale",
  exp = "Lighting.ExposureCompensation", shadow = "Lighting.ShadowSoftness", dens = "Atmosphere.Density", off = "Atmosphere.Offset",
  acol = "Atmosphere.Color", adec = "Atmosphere.Decay", glare = "Atmosphere.Glare", haze = "Atmosphere.Haze",
  bloomI = "NightBloom.Intensity", bloomS = "NightBloom.Size", bloomT = "NightBloom.Threshold", rays = "SunShafts.Intensity",
  raysSpread = "SunShafts.Spread", ccB = "NightGrade.Brightness", ccC = "NightGrade.Contrast", ccS = "NightGrade.Saturation",
  ccTint = "NightGrade.TintColor" }

local function with(base, over)
  local t = {}
  for k, v in pairs(base) do t[k] = v end
  for k, v in pairs(over) do t[k] = v end
  return t
end

---------------------------------------------------------------- 钢城（规格 5.1；训练场、岛图也照它）
local CITY = {}
CITY.day = { bright = 3.0, amb = RGB(22, 24, 28), oamb = RGB(86, 92, 104), top = RGB(255, 243, 224), bot = RGB(44, 42, 38),
  diff = 0.75, spec = 0.8, exp = 0, shadow = 0.18, dens = 0.08, off = 0.14, acol = RGB(198, 210, 226), adec = RGB(104, 120, 148),
  glare = 0.25, haze = 0.7, bloomI = 0.5, bloomS = 24, bloomT = 1.25, rays = 0.04, raysSpread = 0.45,
  ccB = 0, ccC = 0.1, ccS = 0.05, ccTint = RGB(255, 251, 246) }
-- 黄昏：低太阳的暖侧光（Top 橙）、天光偏紫红、影子软一点，空气比白天浓一点（0.1）、太阳周围一大片金色（Glare 0.95、Haze 1.1），光束最明显
CITY.dusk = { bright = 2.2, amb = RGB(24, 20, 22), oamb = RGB(96, 80, 78), top = RGB(255, 158, 90), bot = RGB(50, 40, 48),
  diff = 0.55, spec = 0.7, exp = 0.12, shadow = 0.26, dens = 0.1, off = 0.1, acol = RGB(240, 166, 112), adec = RGB(128, 74, 82),
  glare = 0.95, haze = 1.1, bloomI = 0.75, bloomS = 30, bloomT = 1.05, rays = 0.14, raysSpread = 0.8,
  ccB = 0.01, ccC = 0.12, ccS = 0.12, ccTint = RGB(255, 238, 222) }
-- 夜里：冷蓝的月光（Top 138,156,206）、环境光压得很低，泛光门槛低（灯、火、曳光起光晕），调色去饱和、偏冷
CITY.night = { bright = 2.0, amb = RGB(8, 10, 14), oamb = RGB(34, 40, 56), top = RGB(138, 156, 206), bot = RGB(6, 8, 14),
  diff = 0.25, spec = 0.55, exp = 0.45, shadow = 0.4, dens = 0.085, off = 0.1, acol = RGB(42, 52, 74), adec = RGB(12, 14, 24),
  glare = 0, haze = 0.6, bloomI = 1.15, bloomS = 34, bloomT = 0.95, rays = 0, raysSpread = 0.45,
  ccB = 0, ccC = 0.12, ccS = -0.16, ccTint = RGB(214, 226, 255) }
-- 清晨：黄昏那套，太阳偏粉、天偏淡粉，晨雾（Haze 1.2，比黄昏多一点），颜色没黄昏那么浓
CITY.dawn = with(CITY.dusk, { top = RGB(255, 190, 150), acol = RGB(220, 180, 166), adec = RGB(120, 90, 100), glare = 0.7, haze = 1.2, ccS = 0.06 })

---------------------------------------------------------------- 训练场：白天大气淡一点、地面反光偏暖土色；黄昏、夜里同钢城
local RANGE = {
  day = with(CITY.day, { dens = 0.07, haze = 0.6, bot = RGB(52, 46, 38) }),
  dusk = CITY.dusk, dawn = CITY.dawn, night = CITY.night,
}

---------------------------------------------------------------- 沙海（规格 5.2）：沙地把光反上来（Bottom 暖）、太阳刺眼一点；坦克一两公里对射，大气不要比这再浓
local SANDS = {}
SANDS.day = { bright = 3.4, amb = RGB(30, 26, 22), oamb = RGB(112, 100, 84), top = RGB(255, 240, 212), bot = RGB(96, 76, 54),
  diff = 0.55, spec = 0.7, exp = -0.12, shadow = 0.15, dens = 0.085, off = 0.12, acol = RGB(224, 206, 174), adec = RGB(178, 146, 106),
  glare = 0.45, haze = 0.8, bloomI = 0.45, bloomS = 24, bloomT = 1.3, rays = 0.05, raysSpread = 0.5,
  ccB = 0, ccC = 0.1, ccS = 0, ccTint = RGB(255, 246, 232) }
SANDS.dusk = { bright = 2.5, amb = RGB(28, 22, 20), oamb = RGB(112, 84, 70), top = RGB(255, 150, 78), bot = RGB(96, 62, 44),
  diff = 0.45, spec = 0.65, exp = 0.05, shadow = 0.24, dens = 0.1, off = 0.08, acol = RGB(242, 152, 92), adec = RGB(152, 72, 52),
  glare = 1.0, haze = 1.2, bloomI = 0.7, bloomS = 30, bloomT = 1.05, rays = 0.16, raysSpread = 0.85,
  ccB = 0.01, ccC = 0.12, ccS = 0.1, ccTint = RGB(255, 234, 214) }
SANDS.night = { bright = 1.9, amb = RGB(10, 9, 8), oamb = RGB(42, 40, 42), top = RGB(176, 178, 204), bot = RGB(12, 10, 10),
  diff = 0.25, spec = 0.5, exp = 0.35, shadow = 0.38, dens = 0.085, off = 0.1, acol = RGB(66, 58, 54), adec = RGB(22, 17, 14),
  glare = 0, haze = 0.8, bloomI = 1.1, bloomS = 34, bloomT = 0.95, rays = 0, raysSpread = 0.5,
  ccB = 0, ccC = 0.1, ccS = -0.14, ccTint = RGB(238, 232, 240) }
-- 清晨（照钢城的改法推）：沙漠的早上干冷、霾比傍晚少一点
SANDS.dawn = with(SANDS.dusk, { top = RGB(255, 186, 140), acol = RGB(228, 182, 150), adec = RGB(136, 96, 88), glare = 0.75, haze = 1.1, ccS = 0.05 })

---------------------------------------------------------------- 雪山（规格 5.3）：雪把天光反上来（Bottom 冷蓝、影子里不发黑）；白天压一档曝光；夜里月光照雪、冷蓝
local SNOW = {}
SNOW.day = { bright = 3.1, amb = RGB(28, 32, 40), oamb = RGB(96, 110, 134), top = RGB(255, 250, 242), bot = RGB(92, 106, 130),
  diff = 0.9, spec = 0.95, exp = -0.35, shadow = 0.14, dens = 0.09, off = 0.24, acol = RGB(210, 224, 242), adec = RGB(112, 136, 172),
  glare = 0.4, haze = 0.8, bloomI = 0.55, bloomS = 24, bloomT = 1.2, rays = 0.07, raysSpread = 0.5,
  ccB = 0, ccC = 0.14, ccS = 0, ccTint = RGB(244, 249, 255) }
-- 高山晚霞：雪坡染成橙粉、背阴的一面冷紫
SNOW.dusk = { bright = 2.3, amb = RGB(26, 26, 36), oamb = RGB(118, 106, 136), top = RGB(255, 172, 124), bot = RGB(84, 86, 124),
  diff = 0.7, spec = 0.85, exp = -0.1, shadow = 0.22, dens = 0.1, off = 0.18, acol = RGB(242, 178, 152), adec = RGB(112, 100, 152),
  glare = 0.85, haze = 1.1, bloomI = 0.7, bloomS = 30, bloomT = 1.05, rays = 0.16, raysSpread = 0.8,
  ccB = 0.01, ccC = 0.14, ccS = 0.1, ccTint = RGB(255, 240, 236) }
SNOW.night = { bright = 2.0, amb = RGB(16, 20, 30), oamb = RGB(52, 62, 90), top = RGB(176, 196, 240), bot = RGB(20, 24, 38),
  diff = 0.3, spec = 0.6, exp = 0.45, shadow = 0.35, dens = 0.085, off = 0.16, acol = RGB(54, 66, 96), adec = RGB(14, 18, 30),
  glare = 0, haze = 0.6, bloomI = 1.0, bloomS = 32, bloomT = 0.95, rays = 0, raysSpread = 0.5,
  ccB = 0, ccC = 0.12, ccS = -0.1, ccTint = RGB(210, 224, 255) }
-- 清晨（照钢城的改法推）：日出前后的粉色高山（alpenglow）
SNOW.dawn = with(SNOW.dusk, { top = RGB(255, 198, 172), acol = RGB(228, 192, 192), adec = RGB(112, 106, 156), glare = 0.7, haze = 1.2, ccS = 0.06 })

L.LOOK = { city = CITY, range = RANGE, sands = SANDS, snow = SNOW }

-- 纬度（规格 5.0，可选）：太阳更低、影子更长，更像战雷的侧光；原来全图 23 度（中午太阳几乎在头顶，影子短、画面平）。
--   客户端 DayNight 先在 6 点、18 点各看一眼太阳高度：Roblox 换纬度要是连日出日落也挪了（昼夜按 6 点日出、18 点日落算），退回 LAT0
L.LAT = { city = 48, sands = 29, snow = 58, range = 40 }
L.LAT0 = 23
-- 全局风（格/秒，约 2～4 米/秒）：烟、尘、草跟着一个方向飘（粒子开 WindAffectsDrag 的才吃这个）；暴风雨（Warfx.lua）在这个基础上加大
L.WIND = { city = Vector3.new(5, 0, 2), sands = Vector3.new(9, 0, 3), snow = Vector3.new(11, 0, -5), range = Vector3.new(4, 0, 2) }

-- 哪一套：p（镜头位置）在训练场那块（Zones.RANGE）是训练场，别处是这一局的战场（岛图、大厅照战场那张）
function L.keyFor(Map, p)
  local Z = Map and Map.Zones
  if p and Z and Z.inRange and Z.inRange(p.X, p.Z) then return "range" end
  if Map and (Map.SNOW or Map.NAME == "snow") then return "snow" end
  if Map and (Map.DESERT or Map.NAME == "sands") then return "sands" end
  return "city"
end

local function smooth(a, b, v)
  local t = math.clamp((v - a) / (b - a), 0, 1)
  return t * t * (3 - 2 * t)
end
-- 黄昏 / 清晨的权重（太阳高度 alt：−1 半夜 ～ 1 正午）：日落前后（alt 0.05，约 17:48）最浓 0.85，alt 0.3（16:50）和 −0.2（18:46）是 0；
--   同 Warfx 云的颜色那一段（原来 alt −0.18 那里一刀切掉，插值跳一下：去掉）
function L.twW(alt)
  return math.clamp(1 - math.abs(alt - 0.05) / 0.25, 0, 1) * 0.85
end
-- 太阳本身的颜色（ColorShift_Top 照的是太阳或月亮）、光束：太阳落下去以后（alt < 0）就没有暖色的直射光了，
--   这两项的黄昏权重跟着太阳落山收掉（alt −0.12，约 18:28 收完）；不然日落后月亮从东边升起来照成橙色
function L.twTop(alt)
  return L.twW(alt) * smooth(-0.12, 0.02, alt)
end
-- 钟点 → 混合用的几个权重（DC = DayClock）
function L.weights(clock, DC)
  local alt = DC.sunAlt(clock)
  return DC.dayK(clock), L.twW(alt), L.twTop(alt), clock < 12
end

local function mix(a, b, t)
  if type(a) == "number" then return a + (b - a) * t end
  return a:Lerp(b, t)
end
-- 混合好的一套：key 哪张图，dayK 0 夜里 ～ 1 白天，tw 黄昏权重，twTop 太阳颜色、光束用的黄昏权重，dawn 上午（用清晨那份）；out 复用的表
function L.at(key, dayK, tw, twTop, dawn, out)
  local P = L.LOOK[key] or CITY
  local T = dawn and P.dawn or P.dusk
  local N, D = P.night, P.day
  out = out or {}
  for _, k in ipairs(L.KEYS) do
    local v = mix(N[k], D[k], dayK)
    local w = (k == "top" or k == "rays") and twTop or tw
    if w > 0 then v = mix(v, T[k], w) end
    out[k] = v
  end
  return out
end

return L
