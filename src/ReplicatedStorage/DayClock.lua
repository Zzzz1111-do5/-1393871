-- 全面大战场——昼夜钟点（服务器、客户端共用：同一套算法、同一个服务器时钟，谁看到的都是同一个钟点）
--   用户 11-18 锁过晚上（Config.DayNight.lockNight）；用户 11-25：「给沙漠地图做个昼夜更替」——打开昼夜更替：
--   · 一圈 day + dusk + night + dawn 分钟：白天 7:00～17:00、黄昏 17:00～19:30、夜里 19:30～次日 4:30、清晨 4:30～7:00
--     （钟点在每段里匀速走；白天长、夜里也够打一仗，日出日落各有几分钟慢慢变）
--   · 跨局接着走，不每局从早上重来：服务器开服时按 start 点记下 workspace 属性 DayT0（这一圈从哪一刻起算）
--   · workspace 属性 DayFix 是数：钟点钉死在那个点（PvE 夜战关卡）；没有就按 DayT0 走
--   DC.clock() 现在几点（0～24）；DC.dayK(钟点) 0 夜里 ～ 1 白天；DC.phase(钟点) "dawn" / "day" / "dusk" / "night"；
--   DC.t0For(钟点, 服务器时刻) 要让「这一刻」是这个钟点，DayT0 该写多少
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("Config"))

local DC = {}
local DN = Config.DayNight or {}

local function smooth(a, b, v)
  local t = math.clamp((v - a) / (b - a), 0, 1)
  return t * t * (3 - 2 * t)
end

-- 一圈里的比例 → 钟点（单调增；超过 24 的取余）：{ 比例, 钟点 }
local DAY, DUSK, NIGHT, DAWN = DN.day or 14, DN.dusk or 3, DN.night or 12, DN.dawn or 3
local TOTAL = DAY + DUSK + NIGHT + DAWN
local KEY = { { 0, 7 }, { DAY / TOTAL, 17 }, { (DAY + DUSK) / TOTAL, 19.5 }, { (DAY + DUSK + NIGHT) / TOTAL, 28.5 }, { 1, 31 } }
DC.PERIOD = TOTAL * 60   -- 一圈多少秒
DC.KEY = KEY

function DC.clockAt(f)
  f = f % 1
  for i = 1, #KEY - 1 do
    local a, b = KEY[i], KEY[i + 1]
    if f <= b[1] then return (a[2] + (b[2] - a[2]) * (f - a[1]) / (b[1] - a[1])) % 24 end
  end
  return KEY[#KEY][2] % 24
end

-- 钟点 → 一圈里的比例（clockAt 倒过来）
function DC.fracOf(clock)
  local c = clock % 24
  if c < 7 then c += 24 end   -- 一圈从 7:00 起算：0:00～7:00 算进 24～31
  for i = 1, #KEY - 1 do
    local a, b = KEY[i], KEY[i + 1]
    if c <= b[2] then return a[1] + (b[1] - a[1]) * (c - a[2]) / (b[2] - a[2]) end
  end
  return 0
end

function DC.serverNow()
  local ok, t = pcall(function() return workspace:GetServerTimeNow() end)
  return ok and t or os.clock()
end

function DC.t0For(clock, now)
  return (now or DC.serverNow()) - DC.fracOf(clock) * DC.PERIOD
end

function DC.clock()
  if DN.lockNight then return DN.clock or 2.3 end
  local fix = workspace:GetAttribute("DayFix")
  if type(fix) == "number" then return fix % 24 end
  local t0 = workspace:GetAttribute("DayT0")
  if type(t0) ~= "number" then return DN.start or 15.5 end   -- 服务器还没写（刚进服那一下）
  return DC.clockAt((DC.serverNow() - t0) / DC.PERIOD)
end

function DC.sunAlt(clock) return math.sin((clock - 6) / 12 * math.pi) end   -- 太阳高度：−1 半夜 ～ 1 正午
function DC.dayK(clock) return smooth(-0.08, 0.22, DC.sunAlt(clock)) end

function DC.phase(clock)
  local c = clock % 24
  if c >= 4.5 and c < 7.5 then return "dawn" end
  if c >= 7.5 and c < 17 then return "day" end
  if c >= 17 and c < 19.5 then return "dusk" end
  return "night"
end

return DC
