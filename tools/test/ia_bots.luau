--!nocheck
-- 机器人测试：一个真人（攻方）、其余全是机器人，打几分钟——补人数、守方守据点、攻方坐艇抢滩、交火、占领；量服务器每步耗时
-- 用法（仓库根目录）：lune run tools/test/ia_bots.luau <rbxlx> [打几分钟，默认 6]
local process = require("@lune/process")
local H = require("./harness")
H.quietWarn = true
local minutes = tonumber(process.args[2]) or 6
H.boot(process.args[1], { ds = "mock" })

local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end

H.run(0.5)
local G = H.Gs.server
G.Config.Bots.minPerTeam = 18   -- 正式服关了（用户 11-18：把 AI 士兵去掉），这里打开，测机器人代码还能用
H.runUntil(function() return G.worldReady end, 120)
local pl = H.addPlayer("P1", 4001)
H.run(3)
local BC = G.Config.Bots
local P = G.P[pl]
print("① 补人数（真人 1 个，在" .. P.team .. "）")
local nA, nD = G.botCount("atk"), G.botCount("def")
local wantA = BC.minPerTeam - ((P.team == "atk") and 1 or 0)
local wantD = BC.minPerTeam - ((P.team == "def") and 1 or 0)
check(nA == wantA and nD == wantD, string.format("机器人 攻 %d / 守 %d（应 %d / %d）", nA, nD, wantA, wantD))

local function ents(kind, team)
	local n = 0
	for _, e in ipairs(G.ents) do if e.alive and e.kind == kind and (not team or e.team == team) then n += 1 end end
	return n
end
H.runUntil(function() return G.round.phase == "battle" end, 60)
check(ents("bot", "def") >= nD - 1, "准备阶段守方机器人都出生了：" .. ents("bot", "def"))
-- 守方都在据点附近
local near = 0
for _, e in ipairs(G.ents) do
	if e.alive and e.kind == "bot" and e.team == "def" then
		for _, p in ipairs(G.Map.POINTS) do
			local d = ((e.root.CFrame.Position.X - p.x) ^ 2 + (e.root.CFrame.Position.Z - p.z) ^ 2) ^ 0.5
			if d < 160 then near += 1 break end
		end
	end
end
check(near >= ents("bot", "def") * 0.7, "守方大多在据点附近：" .. near)

print("② 开战：攻方坐艇抢滩")
H.run(3)
check(ents("lcm") >= 1, "有登陆艇在开：" .. ents("lcm"))
local landed = H.runUntil(function()
	for _, e in ipairs(G.ents) do
		if e.alive and e.kind == "bot" and e.team == "atk" and e.bot.state == "move" then return true end
	end
	return false
end, 60)
check(landed, "攻方机器人上岸了")

print(string.format("③ 打 %d 分钟", minutes))
local stepT, stepN, worst, slow = 0, 0, 0, 0
local orig = G.botsStep
G.botsStep = function(dt)
	local c = os.clock()
	orig(dt)
	local d = os.clock() - c
	stepT += d
	stepN += 1
	worst = math.max(worst, d)
	if d > 0.008 then slow += 1 end
end
-- 分开量：开枪（射线）占多少
local shotT, shotN = 0, 0
local origShot = G.botShot
G.botShot = function(...)
	local c = os.clock()
	origShot(...)
	shotT += os.clock() - c
	shotN += 1
end
local mapT = 0
local origLC = G.Map.lineClear
G.Map.lineClear = function(...)
	local c = os.clock()
	local r = origLC(...)
	mapT += os.clock() - c
	return r
end
local t0 = H.now
local lastPrint = H.now
while H.now - t0 < minutes * 60 and G.round.phase == "battle" do
	H.run(5)
	if H.now - lastPrint >= 60 then
		lastPrint = H.now
		local caps, kills = {}, 0
		for _, p in ipairs(G.Map.POINTS) do
			local s = G.points[p.id]
			table.insert(caps, string.format("%s:%s%.0f%%", p.id, s.owner, s.prog * 100))
		end
		local k = { atk = 0, def = 0 }
		for _, row in ipairs(G.botBoard()) do k[row.t] += row.k end
		print(string.format("  %.0f 秒：机器人在场 攻 %d 守 %d，击杀 攻 %d 守 %d，艇 %d，据点 %s", H.now - t0, ents("bot", "atk"), ents("bot", "def"), k.atk, k.def, ents("lcm"), table.concat(caps, " ")))
	end
end
if process.args[3] == "v" then   -- 攻方机器人都在干什么
	for _, e in ipairs(G.ents) do
		if e.alive and e.kind == "bot" then
			local B = e.bot
			local p = e.root.CFrame.Position
			local g = B.detour or B.goal
			print(string.format("  %s %s %-6s 在 (%.0f, %.0f, %.0f) %s 目标点 %s 去 %s 交火 %s", B.team, B.name, B.state, p.X, p.Y, p.Z, G.Map.landOf(p.X, p.Z),
				tostring(B.target or B.guard), g and string.format("(%.0f, %.0f)%s", g.X, g.Z, B.detour and "绕" or "") or "-", B.tgtPos and string.format("%.0f 格", (B.tgtPos - p).Magnitude) or "-"))
		end
	end
end
local k = { atk = 0, def = 0 }
local d = { atk = 0, def = 0 }
for _, row in ipairs(G.botBoard()) do k[row.t] += row.k d[row.t] += row.d end
check(k.atk + k.def > 10, string.format("交火了：击杀 攻 %d 守 %d，阵亡 攻 %d 守 %d", k.atk, k.def, d.atk, d.def))
local capped = 0
for _, s in pairs(G.points) do if s.owner == "atk" then capped += 1 end end
if minutes >= 5 then check(capped >= 1 or G.round.phase ~= "battle", "攻方拿下了据点：" .. capped .. " 个") else print("  攻方拿下了据点：" .. capped .. " 个") end
print(string.format("  其中开枪 %d 次共 %.1f 秒（每次 %.2f 毫秒），视线检查共 %.1f 秒；机器人步总共 %.1f 秒", shotN, shotT, shotT / math.max(1, shotN) * 1000, mapT, stepT))
check(stepN > 0, string.format("机器人每步平均 %.2f 毫秒，最慢 %.1f 毫秒，超过 8 毫秒 %d 次（测试台里，真服务器快几倍）", stepT / math.max(1, stepN) * 1000, worst * 1000, slow))

H.summary()
for i, w in ipairs(H.warns) do if i <= 8 then print("  警告：" .. w.side .. " " .. w.msg) end end
if #H.errors > 0 then fails += 1 end
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
