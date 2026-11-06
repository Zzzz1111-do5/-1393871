--!nocheck
-- 性能：开服 + 6 个玩家（建满楼、打一仗）后数场景里的零件，按顶层文件夹分；客户端每帧的开销（模拟时间里的脚本耗时，只能比大小）
-- 用法：lune run perf.luau <rbxlx> [零件上限，默认 30000]
local process = require("@lune/process")
local H = require("./harness")
H.quietWarn = true
local LIMIT = tonumber(process.args[2]) or 30000
H.boot(process.args[1], { ds = "mock" })
H.run(2)

local function isPart(d)
	return d:IsA("BasePart") and d.ClassName ~= "Terrain"
end
local function count(root)
	local n = 0
	for _, d in root:GetDescendants() do
		if isPart(d) then n += 1 end
	end
	return n
end
-- 测试台里几个客户端共用一个 workspace：Client 开头的文件夹（各客户端自己画的单位、特效）每个名字只算一份，
-- 得到的是一个玩家的电脑上实际有的零件数
local function report(title)
	local rows, byName, total = {}, {}, 0
	for _, c in H.workspace:GetChildren() do
		local n = isPart(c) and 1 or count(c)
		if n > 0 then
			if string.sub(c.Name, 1, 6) == "Client" then
				local r = byName[c.Name]
				if not r then
					r = { c.Name, 0 }
					byName[c.Name] = r
					table.insert(rows, r)
				end
				r[2] = math.max(r[2], n)
			else
				table.insert(rows, { c.Name, n })
			end
		end
	end
	for _, r in rows do total += r[2] end
	table.sort(rows, function(a, b) return a[2] > b[2] end)
	print(string.format("%s：一个玩家那里有零件 %d 个", title, total))
	for i, r in rows do
		if i > 12 then break end
		print(string.format("    %-14s %6d", r[1], r[2]))
	end
	return total
end

local G = H.Gs.server
local base0 = report("① 空服")
local plots = H.workspace:FindFirstChild("Plots")
if plots then
	local one = plots:GetChildren()[1]
	if one then
		local rows = {}
		for _, c in one:GetChildren() do
			local n = isPart(c) and 1 or count(c)
			if n > 0 then table.insert(rows, { c.Name, n }) end
		end
		table.sort(rows, function(a, b) return a[2] > b[2] end)
		print("    一块空基地（" .. one.Name .. "）：")
		for i, r in rows do
			if i > 10 then break end
			print(string.format("      %-12s %6d", r[1], r[2]))
		end
	end
end

-- 6 个人进服，楼全盖满、兵买一些
local players = {}
for i = 1, G.Config.PlotCount do
	local pl = H.addPlayer("P" .. i, 7000 + i)
	table.insert(players, pl)
	H.run(1)
end
H.run(5)
local function act(pl, ...)
	local a = table.pack(...)
	local co = coroutine.create(function() H.Gs[pl.Name].R.Action:FireServer(table.unpack(a, 1, a.n)) end)
	H.ctx = pl
	coroutine.resume(co)
	H.ctx = nil
end
for _, pl in players do
	local st = G.states[pl]
	st.data.cash = 1e9
end
for _ = 1, 16 do
	for _, pl in players do
		local st = G.states[pl]
		local plotF = H.workspace.Plots["Plot" .. st.plot.index]
		for _, b in G.Config.Buildings do
			local m = plotF.Pads:FindFirstChild("Pad_" .. b.id)
			if m and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then
				H.ev(m.Pad, "Touched"):Fire(pl.Character.HumanoidRootPart)
			end
		end
	end
	H.run(1.3)
end
for _, pl in players do
	for _ = 1, 3 do act(pl, "hq") H.run(0.2) end
	for _ = 1, 25 do act(pl, "tech") H.run(0.05) end
	for _, t in { "tank", "tank", "heavytank", "ifv", "aa", "sam", "heli", "attacker", "fighter", "inf", "inf", "medic", "arty" } do
		act(pl, "buy", t)
		H.run(0.1)
	end
end
H.run(25)
local full = report("② 6 人、楼盖满、各买 13 个兵")

-- 都去打仗
for _, pl in players do
	act(pl, "battle")
	H.run(0.3)
end
H.run(12)
local war = report("③ 6 个人同时在打仗（开打 12 秒）")

-- 客户端：一帧要做的事（模拟时间里量 os.clock，只能比大小）
local t0 = os.clock()
local f0 = H.frame
H.run(5)
local per = (os.clock() - t0) / math.max(1, H.frame - f0) * 1000
print(string.format("④ 6 个客户端 + 服务器，模拟里一帧约 %.1f 毫秒（Lune 解释执行、含测试台开销，只能和以前比）", per))

H.summary()
local bad = (math.max(base0, full, war) > LIMIT) or #H.errors > 0
print(string.format("性能：最多 %d 个零件（上限 %d），脚本错误 %d 个", math.max(base0, full, war), LIMIT, #H.errors))
if bad then process.exit(1) end
