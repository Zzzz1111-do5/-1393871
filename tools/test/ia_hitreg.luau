--!nocheck
-- 命中判定的延迟补偿（服务器 Rewind.lua + 客户端 View.lua 的 G.viewRay；同 tools/mock/hitreg.lua）：
--   跑动的小兵、玩家，按开枪的人屏幕上那一刻的位置判定；太久以前的位置、墙后面的不算；客户端准星打在画面上的小兵身上
-- 用法（仓库根目录）：lune run tools/test/ia_hitreg.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF, Inst = roblox.Vector3, roblox.CFrame, roblox.Instance
H.quietWarn = process.args[2] ~= "v"

H.boot(process.args[1], { ds = "mock" })
local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end
local function remote(pl, name, ...)
	local a = table.pack(...)
	local prev = H.ctx
	H.ctx = pl
	local co = coroutine.create(function() H.Gs[pl.Name].R[name]:FireServer(table.unpack(a, 1, a.n)) end)
	coroutine.resume(co)
	H.ctx = prev
end

print("① 开服、两个人进来、开战")
H.run(0.5)
local G = H.Gs.server
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)
local p1, p2 = H.addPlayer("P1", 8201), H.addPlayer("P2", 8202)
H.run(2)
for _, pl in ipairs({ p1, p2 }) do remote(pl, "Act", "pickTeam", G.P[pl].team) end
H.run(0.5)
local P1, P2 = G.P[p1], G.P[p2]
check(P1.team ~= P2.team, "两个人分在两边")
H.runUntil(function() return G.round.phase == "battle" end, 40)
local function spawnOf(P) return (P.team == "atk") and "fleet" or "camp" end
remote(p1, "Act", "deploy", "rifle", spawnOf(P1))
remote(p2, "Act", "deploy", "rifle", spawnOf(P2))
H.run(3)
check(P1.alive and P2.alive and p1.Character and p2.Character, "两个人都出生了")
check(G.rewindShot ~= nil and G.rewindTrace ~= nil, "服务器有延迟补偿（Rewind.lua）")

-- 场地：海面上空，开枪的人站在 O，目标在北边 40 格处左右跑
local O = V3.new(2000, 60, 4000)
local function place(ch, p)
	ch:PivotTo(CF.new(p))
	local h = ch:FindFirstChild("HumanoidRootPart")
	if h then h.Anchored = true end
end
local function placeShooter()
	place(p1.Character, O)
	local tool = p1.Character:FindFirstChildOfClass("Tool") or p1.Backpack:FindFirstChild("m4")
	if tool and tool.Parent ~= p1.Character then tool.Parent = p1.Character end
end
placeShooter()
local function head() return p1.Character.Head.Position end
local CA = H.Gs[p1.Name]
CA.perfK = 100   -- 镜头可能停在远处：把客户端「远了收起来」的距离放大，小兵的样子照常插值

local e = G.newEnt({ kind = "bot", team = P2.team, cat = "inf", hp = 1000, size = V3.new(2.2, 5.6, 1.6), cf = CF.new(O.X - 30, O.Y, O.Z - 40), extra = { headTop = 1.4 } })
local function posAgo(list, dt)
	local t = H.now - dt
	for i = #list, 2, -1 do
		local a, b = list[i - 1], list[i]
		if a.t <= t then
			local k = (t - a.t) / math.max(1e-4, b.t - a.t)
			return a.p + (b.p - a.p) * k
		end
	end
	return list[1].p
end
local dirX = 1
local function runTarget(dur, speed, mover, list)
	local t = 0
	while t < dur do
		local p = mover()
		local np = p + V3.new(dirX * speed / 30, 0, 0)
		if np.X > O.X + 30 then dirX = -1 elseif np.X < O.X - 30 then dirX = 1 end
		mover(np)
		table.insert(list, { t = H.now, p = np })
		placeShooter()
		H.run(1 / 30, 1 / 30)
		t += 1 / 30
	end
end
local function entMover(np)
	if np then G.moveEnt(e, CF.new(np)) return nil end
	return e.root.CFrame.Position
end

print("② 跑动的小兵：瞄着「画面上」的位置（往回 0.25 秒）开枪")
local track = {}
runTarget(1.2, 14, entMover, track)
local aim = posAgo(track, 0.25)
check(G.rayBox(head(), (aim - head()).Unit, e.root.CFrame, e.root.Size, 500) == nil, "按现在的位置这一枪是打空的（原来就是这样不算）")
local hp0 = e.hp
for _ = 1, 3 do
	runTarget(0.1, 14, entMover, track)
	remote(p1, "Shoot", "m4", posAgo(track, 0.25))
end
H.run(0.05)
check(e.hp < hp0, string.format("延迟补偿以后打中了（血 %d → %d）", hp0, e.hp))

print("③ 太久以前的位置（0.9 秒前）不算")
local hp1 = e.hp
for _ = 1, 3 do
	runTarget(0.1, 14, entMover, track)
	local old = posAgo(track, 0.9)
	if (old - e.root.CFrame.Position).Magnitude > 6 then remote(p1, "Shoot", "m4", old) end
end
H.run(0.05)
check(e.hp == hp1, string.format("0.9 秒前的位置打不中（血 %d → %d）", hp1, e.hp))

print("④ 墙挡着：往回找的也打不穿")
runTarget(0.6, 14, entMover, track)
local behind = posAgo(track, 0.25)
local wall = Inst.new("Part")
wall.Anchored = true
wall.Size = V3.new(12, 12, 1)
wall.CFrame = CF.lookAt(head() + (behind - head()) * 0.5, behind)
wall.Parent = H.workspace
local hp2 = e.hp
remote(p1, "Shoot", "m4", behind)
H.run(0.05)
check(e.hp == hp2, string.format("墙后面的打不中（血 %d → %d）", hp2, e.hp))
wall:Destroy()

print("⑤ 跑动的真人：瞄着 0.22 秒前的位置开枪")
local ptrack = {}
local hrp = p2.Character.HumanoidRootPart
local function charMover(np)
	if np then place(p2.Character, np) return nil end
	return hrp.Position
end
place(p2.Character, V3.new(O.X - 20, O.Y, O.Z - 45))
G.moveEnt(e, CF.new(O.X + 400, O.Y, O.Z))
runTarget(1.2, 16, charMover, ptrack)
local hum = p2.Character:FindFirstChildOfClass("Humanoid")
local h0 = hum.Health
for _ = 1, 2 do
	runTarget(0.1, 16, charMover, ptrack)
	remote(p1, "Shoot", "m4", posAgo(ptrack, 0.22))
end
H.run(0.05)
check(hum.Health < h0, string.format("打中了跑动的玩家（血 %.0f → %.0f）", h0, hum.Health))

print("⑥ 客户端：准星打在画面上的小兵身上（不是隐形命中盒）")
place(p2.Character, V3.new(O.X + 300, O.Y, O.Z + 300))
G.moveEnt(e, CF.new(O.X - 20, O.Y, O.Z - 40))
track = {}
runTarget(1.5, 14, entMover, track)
local v = CA.views and CA.views[e.model]
check(v ~= nil and v.fl ~= nil, "客户端给这个小兵建了样子、在做快照插值")
if v then
	local lag = (v.cf.Position - e.root.CFrame.Position).Magnitude
	check(lag > 0.5, string.format("画面上的小兵比命中盒晚 %.1f 格", lag))
	local prev = H.ctx
	H.ctx = p1
	local cam = H.workspace.CurrentCamera
	cam.CameraType = roblox.Enum.CameraType.Scriptable
	cam.CFrame = CF.lookAt(head(), v.cf.Position)
	local pAim = CA.aimPoint(600)
	H.ctx = prev
	local off = pAim and (pAim - v.cf.Position).Magnitude or -1
	check(pAim ~= nil and off < 2, string.format("准星的点在画面上的小兵身上（离画面上的中心 %.1f 格）", off))
	local hp3 = e.hp
	remote(p1, "Shoot", "m4", pAim)
	H.run(0.05)
	check(e.hp < hp3, string.format("照客户端的准星点开枪：服务器算打中（血 %d → %d）", hp3, e.hp))
end

H.summary()
for i, w in ipairs(H.warns) do if i <= 20 then print("  警告：" .. w.side .. " " .. w.msg) end end
if #H.errors > 0 then fails += 1 end
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
