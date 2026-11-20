--!nocheck
-- 装甲：跳弹、炮塔掀飞（用户：跳弹也做出来；坦克被打爆盖子可以飞起来，动画逼真一点）
--   ① 炮弹擦着坦克侧面打（离法线 86°）：跳开——几乎不掉血、服务器记一次跳弹、开车的人看到「被弹开了」、客户端画了跳弹（火星 + 声音）
--   ② 正对着侧面打：不跳，照常掉血
--   ③ 坦克被打爆：炮塔连炮飞起来（离开座圈往上好几格），落地弹几下、停在地上
--   用法：lune run tools/test/ia_armor.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF = roblox.Vector3, roblox.CFrame
H.quietWarn = true

H.boot(process.args[1], { ds = "mock" })
H.run(0.5)
local G = H.Gs.server
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)
local p1, p2 = H.addPlayer("P1", 8101), H.addPlayer("P2", 8102)
H.run(2)
local def = (G.P[p1].team == "def") and p1 or p2
H.removePlayer((def == p1) and p2 or p1)
H.run(0.5)
local CD = H.Gs[def.Name]

local fails = 0
local function check(ok, msg)
	print((ok and "  ✓ " or "  ✗ ") .. msg)
	if not ok then fails += 1 end
end
local function as(who, f)
	local prev = H.ctx
	H.ctx = who
	local co = coroutine.create(f)
	coroutine.resume(co)
	H.ctx = prev
end
local function act(who, ...)
	local a = table.pack(...)
	as(who, function() H.Gs[who.Name].R.Act:FireServer(table.unpack(a, 1, a.n)) end)
end
-- 开车的人收到的消息（跳弹的「被弹开了」）
local got = {}
local onMsg0 = CD.onMsg
CD.onMsg = function(kind, key, ...)
	table.insert(got, { kind = kind, key = key })
	if onMsg0 then return onMsg0(kind, key, ...) end
end

act(def, "deploy", "rifle", "camp")
H.run(2)
local tp = H.pad(G, "m1a2")
local e = tp and H.usePad(G, def, tp)
if e then act(def, "enterVeh", e.id) end
H.run(2)
check(e ~= nil and CD.drive ~= nil, "坐上了 M1A2")
if not e then
	H.shutdown()
	process.exit(1)
end

local VD
as(def, function() VD = H.require(H.game:GetService("ReplicatedStorage"):FindFirstChild("VehDefs")) end)
local w = VD.W[e.def.weapons[1]]
local function shoot(from, to)
	G.launch({ kind = "shell", pos = from, vel = (to - from).Unit * 900, grav = false, w = w, src = nil, ignore = {}, life = 2 })
	H.run(0.4)
end

print("① 擦着侧面打（离法线 86°）")
local rc = e.root.CFrame
local half = e.root.Size / 2
local hit = (rc * CF.new(half.X, 0, 0)).Position
local hp0 = e.hp
local ric0 = G.ricochets or 0
local cric0 = CD.ricochetCount or 0
shoot(hit + rc.LookVector * 60 + rc.RightVector * 4.2, hit)
check((G.ricochets or 0) == ric0 + 1, "服务器判了跳弹")
check(e.hp > hp0 - w.dmg * 0.1, string.format("跳开的弹几乎不伤（掉了 %.0f，炮弹伤害 %d）", hp0 - e.hp, w.dmg))
check((CD.ricochetCount or 0) > cric0, "客户端画了跳弹（火星、当的一声）")
local saw = false
for _, m in ipairs(got) do if m.kind == "ric" and m.key == "hit.ricIn" then saw = true end end
check(saw, "开车的人看到「炮弹被装甲弹开了」")

print("② 正对着侧面打")
local hp1 = e.hp
shoot(hit + rc.RightVector * 60, hit)
check((G.ricochets or 0) == ric0 + 1, "正对着打不跳")
check(e.hp < hp1 - w.dmg * 0.3, string.format("照常掉血（掉了 %.0f）", hp1 - e.hp))

print("③ 打爆：炮塔掀飞")
local v = CD.views and CD.views[e.model]
local t0 = v and v.tF and v.tF.Position
G.damageEnt(e, 1e6, nil)
H.run(0.15)
check((CD.tossCount or 0) >= 1 and v ~= nil and v.toss ~= nil, "炮塔掀起来了")
local top = 0
for _ = 1, 30 do
	H.run(0.05)
	if v and v.toss and t0 then top = math.max(top, v.toss.cf.Position.Y - t0.Y) end
end
check(top > 6, string.format("飞起来 %.1f 格高", top))
H.run(5)
check(v ~= nil and v.toss ~= nil and v.toss.rest == true, "落地弹几下停住了")
if v and v.toss and t0 then
	local p = v.toss.cf.Position
	local gy = G.Map.height(p.X, p.Z)
	check(math.abs(p.Y - math.max(gy, -0.5) - 0.4) < 1.5, string.format("停在地上（离地 %.1f 格）", p.Y - gy))
	check((V3.new(p.X, 0, p.Z) - V3.new(t0.X, 0, t0.Z)).Magnitude > 1, string.format("离开了车体（水平挪了 %.1f 格）", (V3.new(p.X, 0, p.Z) - V3.new(t0.X, 0, t0.Z)).Magnitude))
end

print(fails == 0 and "装甲：全部通过" or ("装甲：" .. fails .. " 项没过"))
H.shutdown()
process.exit(fails == 0 and 0 or 1)
