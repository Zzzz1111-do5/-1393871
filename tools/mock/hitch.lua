-- 一阵一阵卡（用户 11-25：「游戏一阵一阵卡 然后枪 坦克 飞机一阵一阵抽搐」）：python3 tools/mock/run.py tools/mock/hitch.lua [先打多少秒] [测多少秒]
--   沙海、机器人打起来以后，逐步（一步 = 客户端一帧 + 服务器一步）记：这一步总共花了多少、客户端每个逐帧回调、服务器每个 G.xxxStep 各花多少；
--   挑出比中位数慢得多的步（尖峰），看是谁、隔多久来一次（周期性的就是「一阵一阵」）。
--   测试台是 Lua 5.4 + 元表模拟（比真 Roblox 慢几倍、射线慢几百倍），只看相对：尖峰是谁、多久一次
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check
local K = dofile(MOCK_DIR .. "/perfkit.lua")(T)
local nums = {}
for x in TEST_ARGS:gmatch("%d+") do nums[#nums + 1] = tonumber(x) end
local warm, secs = nums[1] or 30, nums[2] or 40
local DT = 1 / 30
local SAMPLE = TEST_ARGS:find("sample") ~= nil

-- 按行采样（参数带 sample）：开服前就挂上，后台协程、事件回调的线程也都带着；每一步单独记，尖峰那几步的热点行单独列出来
local cur
if SAMPLE then
  R.sampler = function()
    if not cur then return end
    for lv = 2, 16 do
      local info = debug.getinfo(lv, "Sl")
      if not info then break end
      local src = info.source or ""
      if src:find("/src/", 1, true) then
        local k = (src:match("([^/]+)$") or src) .. ":" .. tostring(info.currentline)
        cur[k] = (cur[k] or 0) + 1
        return
      end
    end
  end
end

local G = T.boot()
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 7501, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "base")
R.run(2)
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
print(string.format("开战后先打 %d 秒", warm))
R.run(warm, 1 / 10)

local timed = { t = {}, n = {} }
K.wrap(G, "Step$", "服务器 ", timed)
local steps = {}
local function snap(tbl) local o = {} for k, v in pairs(tbl) do o[k] = v end return o end
local nSteps = math.floor(secs / DT)
for i = 1, nSteps do
  C.perfT, C.perfMax = {}, {}
  local s0 = snap(timed.t)
  cur = SAMPLE and {} or nil
  local t0 = os.clock()
  R.step(DT)
  local dt = os.clock() - t0
  local parts = {}
  for k, v in pairs(C.perfT or {}) do parts["客户端 " .. k] = v end
  for k, v in pairs(timed.t) do
    local d = v - (s0[k] or 0)
    if d > 0 then parts[k] = d end
  end
  local att = 0
  for _, v in pairs(parts) do att = att + v end
  parts["（没归到谁：引擎模拟、后台协程、事件）"] = math.max(0, dt - att)
  steps[i] = { i = i, dt = dt, parts = parts, hits = cur }
  cur = nil
end

-- 统计
local sorted = {}
for i, s in ipairs(steps) do sorted[i] = s.dt end
table.sort(sorted)
local med = sorted[math.floor(#sorted / 2) + 1]
local p95 = sorted[math.floor(#sorted * 0.95)]
local mx = sorted[#sorted]
print(string.format("一共 %d 步：中位数 %.1f 毫秒、95%% %.1f 毫秒、最慢 %.1f 毫秒（测试台的毫秒，不是真 Roblox 的）", #steps, med * 1000, p95 * 1000, mx * 1000))
-- 每一项：平均、最大，最大那一步是第几步；尖峰（> 3 倍中位数）里它占大头的次数、间隔
local agg = {}
for _, s in ipairs(steps) do
  for k, v in pairs(s.parts) do
    local a = agg[k] or { sum = 0, max = 0, at = 0, spikes = {} }
    agg[k] = a
    a.sum = a.sum + v
    if v > a.max then a.max, a.at = v, s.i end
  end
end
local spikes = {}
for _, s in ipairs(steps) do
  if s.dt > 3 * med then
    local bk, bv = nil, 0
    for k, v in pairs(s.parts) do if v > bv then bk, bv = k, v end end
    spikes[#spikes + 1] = { i = s.i, dt = s.dt, who = bk, v = bv }
    table.insert(agg[bk].spikes, s.i)
  end
end
local rows = {}
for k, a in pairs(agg) do rows[#rows + 1] = { k = k, a = a } end
table.sort(rows, function(x, y) return x.a.max > y.a.max end)
print("单项单步最长（前 14）：")
for j = 1, math.min(14, #rows) do
  local r = rows[j]
  local sp = r.a.spikes
  local gap = ""
  if #sp >= 2 then
    local g = {}
    for q = 2, math.min(#sp, 8) do g[#g + 1] = string.format("%.1f", (sp[q] - sp[q - 1]) * DT) end
    gap = "，尖峰间隔 " .. table.concat(g, " / ") .. " 秒"
  end
  print(string.format("  %-34s 最长 %7.1f 毫秒（第 %d 步）、平均 %6.2f 毫秒，当头号尖峰 %d 次%s", r.k, r.a.max * 1000, r.a.at, r.a.sum / #steps * 1000, #sp, gap))
end
print(string.format("尖峰（> 3 倍中位数）%d 步", #spikes))
for j = 1, math.min(12, #spikes) do
  local s = spikes[j]
  print(string.format("  第 %4d 步（%.1f 秒）%.1f 毫秒：大头 %s %.1f 毫秒", s.i, s.i * DT, s.dt * 1000, tostring(s.who), s.v * 1000))
end
if SAMPLE then
  -- 尖峰那几步合起来的热点行 vs 平常的步
  local sh, nh, ns, nn = {}, {}, 0, 0
  for _, s in ipairs(steps) do
    local into = (s.dt > 3 * med) and sh or nh
    for k, v in pairs(s.hits or {}) do
      into[k] = (into[k] or 0) + v
      if into == sh then ns = ns + v else nn = nn + v end
    end
  end
  local rows2 = {}
  for k, v in pairs(sh) do rows2[#rows2 + 1] = { k = k, v = v } end
  table.sort(rows2, function(a, b) return a.v > b.v end)
  print(string.format("尖峰那几步最热的游戏代码行（共 %d 个样本；平常的步 %d 个样本）：", ns, nn))
  for j = 1, math.min(30, #rows2) do
    print(string.format("  %5.1f%%  %-44s 平常的步里 %d 个", rows2[j].v / math.max(ns, 1) * 100, rows2[j].k, nh[rows2[j].k] or 0))
  end
end
check(#steps == nSteps, "量完了 " .. nSteps .. " 步")
T.summary()
