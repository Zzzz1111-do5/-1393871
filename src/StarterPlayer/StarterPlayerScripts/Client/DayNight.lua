-- Roblox全面大战场（客户端）——昼夜更替（用户：改成昼夜更替吧，一直黑天玩起来有点怪）
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
  local NIGHT = { bright = 2.2, amb = RGB(14, 17, 24), oamb = RGB(38, 45, 62), top = RGB(140, 160, 210), bot = RGB(8, 10, 16), diff = 0.35, spec = 0.9, exp = 0.55,
    fog = RGB(16, 20, 30), dens = 0.21, acol = RGB(44, 54, 76), adec = RGB(12, 15, 24), glare = 0.15, haze = 1.1,
    bloomI = 1.1, bloomT = 1.05, ccSat = -0.12, ccCon = 0.14, ccTint = RGB(222, 232, 255) }
  local DAY = { bright = 3.0, amb = RGB(78, 80, 86), oamb = RGB(132, 134, 140), top = RGB(255, 248, 236), bot = RGB(42, 38, 32), diff = 1, spec = 1, exp = 0,
    fog = RGB(176, 194, 214), dens = 0.17, acol = RGB(196, 208, 224), adec = RGB(96, 112, 136), glare = 0.25, haze = 0.7,
    bloomI = 0.35, bloomT = 1.6, ccSat = 0.04, ccCon = 0.07, ccTint = RGB(255, 255, 255) }
  local DUSK = { top = RGB(255, 168, 108), fog = RGB(206, 150, 120), acol = RGB(228, 160, 120), adec = RGB(170, 86, 58) }

  local dayK, clock = 0, 2.3
  G.dayK = function() return dayK end
  G.isNight = function() return dayK < 0.35 end
  G.clockNow = function() return clock end

  local acc = 1
  local function step(dt)
    acc += dt
    if acc < 0.1 then return end   -- 一秒十次就够顺
    acc = 0
    local t0 = workspace:GetAttribute("DayT0")
    if type(t0) ~= "number" then t0 = 0 end
    local f = ((serverNow() - t0) / PERIOD) % 1
    clock = clockAt(f)
    local alt = math.sin((clock - 6) / 12 * math.pi)   -- 太阳高度（−1 半夜 ～ 1 正午）
    dayK = smooth(-0.08, 0.22, alt)
    local dusk = (alt > -0.18 and alt < 0.3) and (1 - math.abs(alt - 0.05) / 0.25) or 0
    dusk = math.clamp(dusk, 0, 1) * 0.85
    -- 开飞机飞得越高大气越淡、雾越远（用户：飞机视野有点近）
    local cam = workspace.CurrentCamera
    local hk = (G.fly and cam) and smooth(150, 1800, cam.CFrame.Position.Y) or 0
    local nv = G.nvLight == true
    local nk = 1 - dayK
    pcall(function()
      Lighting.ClockTime = clock
      Lighting.Brightness = lerp(NIGHT.bright, DAY.bright, dayK)
      local amb, oamb = lc(NIGHT.amb, DAY.amb, dayK), lc(NIGHT.oamb, DAY.oamb, dayK)
      local exp = lerp(NIGHT.exp, DAY.exp, dayK)
      if nv then   -- 夜视：本地增亮（白天只亮一点点）
        exp += 2.7 * nk + 0.25 * dayK
        amb, oamb = lc(amb, RGB(52, 60, 56), nk), lc(oamb, RGB(96, 110, 100), nk)
      end
      Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.ExposureCompensation = amb, oamb, exp
      Lighting.ColorShift_Top = lc(lc(NIGHT.top, DAY.top, dayK), DUSK.top, dusk)
      Lighting.ColorShift_Bottom = lc(NIGHT.bot, DAY.bot, dayK)
      Lighting.EnvironmentDiffuseScale = lerp(NIGHT.diff, DAY.diff, dayK)
      Lighting.EnvironmentSpecularScale = lerp(NIGHT.spec, DAY.spec, dayK)
      Lighting.FogColor = lc(lc(NIGHT.fog, DAY.fog, dayK), DUSK.fog, dusk)
      Lighting.FogEnd = 12000 + 18000 * hk
      local atm = Lighting:FindFirstChildOfClass("Atmosphere")
      if atm then
        local dens = lerp(NIGHT.dens, DAY.dens, dayK) * (1 - 0.5 * hk)
        if nv then dens = math.max(0.06, dens * 0.55) end
        atm.Density = dens
        atm.Color = lc(lc(NIGHT.acol, DAY.acol, dayK), DUSK.acol, dusk)
        atm.Decay = lc(lc(NIGHT.adec, DAY.adec, dayK), DUSK.adec, dusk)
        atm.Glare = lerp(NIGHT.glare, DAY.glare, dayK) + 0.6 * dusk
        atm.Haze = lerp(NIGHT.haze, DAY.haze, dayK) * (1 - 0.5 * hk)
      end
      local bloom = Lighting:FindFirstChild("NightBloom")
      if bloom then bloom.Intensity, bloom.Threshold = lerp(NIGHT.bloomI, DAY.bloomI, dayK), lerp(NIGHT.bloomT, DAY.bloomT, dayK) end
      local cc = Lighting:FindFirstChild("NightGrade")
      if cc then
        cc.Saturation, cc.Contrast = lerp(NIGHT.ccSat, DAY.ccSat, dayK), lerp(NIGHT.ccCon, DAY.ccCon, dayK)
        cc.TintColor = lc(NIGHT.ccTint, DAY.ccTint, dayK)
      end
    end)
  end
  G.stepDayNight = step
  step(1)
end

return DayNight
