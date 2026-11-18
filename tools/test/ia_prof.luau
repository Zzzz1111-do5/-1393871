--!nocheck
-- 卡顿排查（用户：这游戏一卡一卡的）：一个真人（攻方，步兵在登陆平台）+ 机器人打一段，按回调 / 后台任务记耗时（测试台的 H.prof），
--   打出总耗时最多的、单次最慢的，和每一帧（服务器 + 客户端一起）耗时的分布——测试台不是真 Roblox，绝对数不准，看谁占得多、谁一阵一阵地慢
-- 用法（仓库根目录）：lune run tools/test/ia_prof.luau <rbxlx> [打几秒，默认 60]
local process = require("@lune/process")
local H = require("./harness")
H.quietWarn = true
local secs = tonumber(process.args[2]) or 60
H.boot(process.args[1], { ds = "mock" })

local function as(pl, fn)
	local prev = H.ctx
	H.ctx = pl
	fn()
	H.ctx = prev
end
local function act(pl, ...)
	local a = table.pack(...)
	as(pl, function() H.Gs[pl.Name].R.Act:FireServer(table.unpack(a, 1, a.n)) end)
end

H.run(0.5)
local G = H.Gs.server
H.runUntil(function() return G.worldReady end, 120)
local pl = H.addPlayer("P1", 4001)
H.run(3)
H.runUntil(function() return G.round.phase == "battle" end, 90)
act(pl, "deploy", "rifle", (G.P[pl].team == "atk") and "lhd" or "camp")
H.run(5)
print(string.format("开打：%s 方，机器人 攻 %d / 守 %d，实体 %d", G.P[pl].team, G.botCount("atk"), G.botCount("def"), #G.ents))

-- 服务器的推演步（init.server 每 Config.Tick 调一次）：各自包一层计时，算进 H.prof
local function wrap(name)
	local f = G[name]
	if type(f) ~= "function" then return end
	G[name] = function(...)
		local t0 = os.clock()
		local r = table.pack(f(...))
		if H.prof then
			local k = "服务器步 " .. name
			local r0 = H.prof[k] or { n = 0, t = 0, max = 0 }
			H.prof[k] = r0
			local d = os.clock() - t0
			r0.n += 1 r0.t += d if d > r0.max then r0.max = d end
		end
		return table.unpack(r, 1, r.n)
	end
end
for _, k in ipairs({ "roundStep", "entsStep", "botsStep", "vehStep", "fortsStep", "airStep", "navyStep", "shipStep" }) do wrap(k) end
-- G.try 包的各段（实体按种类、机器人想、开火……）：按名字记
local try0 = G.try
G.try = function(name, f, ...)
	if not H.prof then return try0(name, f, ...) end
	local t0 = os.clock()
	local r = table.pack(try0(name, f, ...))
	local k = "try " .. tostring(name)
	local r0 = H.prof[k] or { n = 0, t = 0, max = 0 }
	H.prof[k] = r0
	local d = os.clock() - t0
	r0.n += 1 r0.t += d if d > r0.max then r0.max = d end
	return table.unpack(r, 1, r.n)
end
-- 地形高度（游戏自己算的：机器人走路、出生、放东西都要），单独记
local Map = G.Map
if Map and Map.height then
	local h0 = Map.height
	Map.height = function(x, z)
		if not H.prof then return h0(x, z) end
		local t0 = os.clock()
		local a, b = h0(x, z)
		local k = "Map.height"
		local r0 = H.prof[k] or { n = 0, t = 0, max = 0 }
		H.prof[k] = r0
		local dd = os.clock() - t0
		r0.n += 1 r0.t += dd if dd > r0.max then r0.max = dd end
		return a, b
	end
end
H.prof = {}
local frames = {}
local dt = 1 / 30
local n = math.floor(secs / dt)
for i = 1, n do
	local t0 = os.clock()
	H.step(dt)
	frames[i] = os.clock() - t0
end
local prof = H.prof
H.prof = nil

local rows = {}
for k, r in pairs(prof) do table.insert(rows, { k = k, n = r.n, t = r.t, max = r.max }) end
table.sort(rows, function(a, b) return a.t > b.t end)
print(string.format("—— 总耗时最多的（%d 帧、模拟 %d 秒）——", n, secs))
for i = 1, math.min(25, #rows) do
	local r = rows[i]
	print(string.format("  %7.1f 毫秒/秒  每次 %6.2f 毫秒  最慢 %7.2f 毫秒  %6d 次  %s", r.t * 1000 / secs, r.t * 1000 / r.n, r.max * 1000, r.n, r.k))
end
table.sort(rows, function(a, b) return a.max > b.max end)
print("—— 单次最慢的 ——")
for i = 1, math.min(15, #rows) do
	local r = rows[i]
	print(string.format("  最慢 %7.2f 毫秒  每次 %6.2f 毫秒  %6d 次  %s", r.max * 1000, r.t * 1000 / r.n, r.n, r.k))
end
local sorted = table.clone(frames)
table.sort(sorted)
local function pct(q) return sorted[math.max(1, math.floor(#sorted * q))] * 1000 end
local over = 0
local mean = 0
for _, f in ipairs(frames) do mean += f if f > 2 * sorted[math.floor(#sorted / 2)] then over += 1 end end
print(string.format("—— 每帧（服务器 + 客户端）：中位 %.1f、90%% %.1f、99%% %.1f、最慢 %.1f 毫秒；比中位慢一倍以上的帧 %d 个（%.1f%%）", pct(0.5), pct(0.9), pct(0.99), sorted[#sorted] * 1000, over, 100 * over / #frames))
-- 尖峰出现的时刻（看是不是周期性的）
local spikes = {}
for i, f in ipairs(frames) do if f > 3 * sorted[math.floor(#sorted / 2)] then table.insert(spikes, string.format("%.1f", i * dt)) end end
print("尖峰时刻（秒）：" .. table.concat(spikes, " ", 1, math.min(#spikes, 60)))
H.shutdown()
