--!nocheck
-- 平衡统计（调试用，不进测试清单）：机器人对打几分钟，记下攻方机器人和登陆艇死在什么上面（工事各类、机器人、其它）
-- 用法：lune run tools/test/ia_balance.luau <rbxlx> [分钟，默认 6]
local process = require("@lune/process")
local H = require("./harness")
H.quietWarn = true
local minutes = tonumber(process.args[2]) or 6
H.boot(process.args[1], { ds = "mock" })
H.run(0.5)
local G = H.Gs.server
H.runUntil(function() return G.worldReady end, 120)
local pl = H.addPlayer("P1", 4001)
H.run(3)
local byKind = {}   -- [被打死的东西] = { [来源] = 次数 }
local function srcName(src)
	if not src then return "?" end
	if src.name and src.name.k then return src.name.k end
	if src.P then return "player" end
	if src.bot or src.B then return "bot" end
	if src.veh or src.e then return "vehicle" end
	return "other:" .. tostring(src.team)
end
local orig = G.damageEnt
G.damageEnt = function(e, amt, src)
	local was = e and e.alive
	orig(e, amt, src)
	if was and e and not e.alive and e.team == "atk" then
		local k = e.kind or "?"
		byKind[k] = byKind[k] or {}
		local s = srcName(src)
		byKind[k][s] = (byKind[k][s] or 0) + 1
	end
end
H.runUntil(function() return G.round.phase == "battle" end, 60)
H.run(minutes * 60)
for k, t in pairs(byKind) do
	local list = {}
	for s, n in pairs(t) do table.insert(list, { s, n }) end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	local parts = {}
	for _, it in ipairs(list) do table.insert(parts, it[1] .. " " .. it[2]) end
	print(string.format("攻方 %s 被打死：%s", k, table.concat(parts, "，")))
end
local pts = {}
for _, p in ipairs(G.Map.POINTS) do
	local st = G.round.points and G.round.points[p.id]
	table.insert(pts, p.id .. ":" .. tostring(st and st.owner))
end
print("据点 " .. table.concat(pts, " "))
H.summary()
