--!nocheck
-- 雷达测试（Hud.lua 右上的方形绿色雷达小地图；没有转圈的扫描线）：友军都显示；敌方步兵在视线里才显示（太远、躲在墙后都不显示）；
--   敌人开了没消音的枪，开枪的地方闪红圈；Config.Radar.allEnemies 打开后墙后的也显示；车（敌我）在范围内就显示
-- 用法（仓库根目录）：lune run tools/test/ia_radar.luau <rbxlx>
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
local function act(pl, ...)
	local a = table.pack(...)
	local prev = H.ctx
	H.ctx = pl
	local co = coroutine.create(function() H.Gs[pl.Name].R.Act:FireServer(table.unpack(a, 1, a.n)) end)
	coroutine.resume(co)
	H.ctx = prev
end

H.run(0.5)
local G = H.Gs.server
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)

print("① 两边各一个人出生")
local p1, p2 = H.addPlayer("P1", 8101), H.addPlayer("P2", 8102)
H.run(2)
for _, pl in ipairs({ p1, p2 }) do act(pl, "pickTeam", G.P[pl].team) end
H.run(0.5)
local atk = (G.P[p1].team == "atk") and p1 or p2
local def = (atk == p1) and p2 or p1
H.runUntil(function() return G.round.phase == "battle" end, 40)
act(atk, "deploy", "rifle", "fleet")
act(def, "deploy", "rifle", "camp")
H.run(3)
local CA = H.Gs[atk.Name]
check(G.P[atk].alive and G.P[def].alive and atk.Character and def.Character, "攻方、守方都出生了")
local box = atk.PlayerGui:FindFirstChild("Radar", true)
check(box ~= nil and box:IsA("CanvasGroup"), "雷达小地图（CanvasGroup 裁边）")
if box then
	local corner = box:FindFirstChildOfClass("UICorner")
	check(box.AnchorPoint.X == 1 and box.AnchorPoint.Y == 0 and box.Position.X.Scale == 1 and box.Position.Y.Scale == 0,
		"在右上角（用户：右上角加个正方形小地图）")
	check(box.Size.X.Offset == box.Size.Y.Offset and corner ~= nil and corner.CornerRadius.Scale == 0 and corner.CornerRadius.Offset <= 4,
		"正方形（不是圆）")
	-- 没有扫描线：框里的 Frame 过一会儿都不转（▲ 跟着朝向转，是字）
	local rot = {}
	for _, d in box:GetDescendants() do
		if d:IsA("Frame") then rot[d] = d.Rotation end
	end
	H.run(0.6)
	local turned = 0
	for d, r in pairs(rot) do
		if d.Parent and d.Rotation ~= r and d.Size.X.Offset > 2 and d.Size.Y.Scale >= 0.5 then turned += 1 end
	end
	check(turned == 0, "没有绕圈转的扫描线")
	local feed = CA.hudParts and CA.hudParts.feed
	if feed then
		check(feed.Position.Y.Offset >= box.Position.Y.Offset + box.Size.Y.Offset, "击杀信息挪到小地图下面（不叠在一起）")
	end
end

local function shown()
	local n = { enemyInf = 0, enemyVeh = 0, friendVeh = 0, ping = 0 }
	for _, s in ipairs(CA.radarShown or {}) do
		if s.kind == "ping" then n.ping += 1
		elseif s.enemy and s.kind == "inf" then n.enemyInf += 1
		elseif s.enemy then n.enemyVeh += 1
		elseif s.kind ~= "inf" then n.friendVeh += 1 end
	end
	return n
end
local hrpA = atk.Character:FindFirstChild("HumanoidRootPart")
local headA = atk.Character:FindFirstChild("Head")
local eye = (headA or hrpA).CFrame.Position
-- 敌人放到 40 格外、从攻方的眼睛看过去没东西挡的地方（攻方在舰队甲板上：前后可能有舰桥、栏杆）
local rp = H.genv.RaycastParams.new()
rp.FilterType = roblox.Enum.RaycastFilterType.Exclude
rp.FilterDescendantsInstances = { atk.Character, def.Character }
local front = nil
for _, o in ipairs({ V3.new(0, 8, -40), V3.new(0, 8, 40), V3.new(40, 8, 0), V3.new(-40, 8, 0), V3.new(0, 30, -30), V3.new(0, 40, 0) }) do
	local p = (hrpA.CFrame * CF.new(o)).Position
	if not front and not H.workspace:Raycast(eye, (p + V3.new(0, 1.5, 0)) - eye, rp) then front = CF.new(p) end
end
check(front ~= nil, "找到一个看得见的地方放敌人")
front = front or (hrpA.CFrame * CF.new(0, 40, 0))
local function putEnemy(cf)
	def.Character:PivotTo(cf)
	local h = def.Character:FindFirstChild("HumanoidRootPart")
	if h then h.Anchored = true end
end

print("② 敌方步兵：看得见才上雷达")
putEnemy(front)
H.run(1)
check(shown().enemyInf == 1, "面前 40 格看得见的敌人上了雷达：" .. shown().enemyInf)
putEnemy(hrpA.CFrame * CF.new(0, 8, -2600))
H.run(2.5)
check(shown().enemyInf == 0, "雷达范围外的敌人不显示")
-- 墙后：中间立一堵墙
putEnemy(front)
local wall = Inst.new("Part")
wall.Anchored = true
wall.Size = V3.new(60, 60, 4)
local mid = (eye + front.Position) / 2
wall.CFrame = CF.lookAt(mid, front.Position)   -- 立在视线中间、正对着敌人
wall.Parent = H.workspace
H.run(2.6)
check(shown().enemyInf == 0, "躲在墙后的敌人不显示（不是透视）")
CA.Config.Radar.allEnemies = true
H.run(0.5)
check(shown().enemyInf == 1, "Config.Radar.allEnemies 打开：墙后的也显示")
CA.Config.Radar.allEnemies = false

print("③ 敌人开枪：开枪的地方闪红圈")
G.fx({ k = "gun", w = "m4", a = front.Position, b = eye, t = "def" })
H.run(0.4)
check(shown().ping >= 1, "敌人开枪的地方闪了红圈")
G.fx({ k = "gun", w = "m4", a = eye + V3.new(5, 0, 0), b = eye + V3.new(5, 0, -50), t = "atk" })
H.run(0.4)
local before = shown().ping
H.run(G.Config.Radar.ping + 0.5)
check(before == 1 and shown().ping == 0, "自己人开枪不闪；红圈过 " .. G.Config.Radar.ping .. " 秒消失")

print("④ 车：友军、敌方在范围内就显示（墙后的敌方车辆也有：雷达回波）")
local function ent(team, dz)
	return G.newEnt({ kind = "veh", team = team, cat = "armor", hp = 500, size = V3.new(8, 6, 16), cf = hrpA.CFrame * CF.new(12, 0, dz) })
end
local ef = ent(atk == p1 and G.P[atk].team or "atk", 30)
local ee = ent("def", -60)
H.run(0.6)
local n = shown()
check(n.friendVeh == 1 and n.enemyVeh == 1, string.format("友军车 %d、敌方车 %d", n.friendVeh, n.enemyVeh))
G.removeEnt(ee)
G.removeEnt(ef)
wall:Destroy()

H.summary()
for i, w in ipairs(H.warns) do if i <= 20 then print("  警告：" .. w.side .. " " .. w.msg) end end
if #H.errors > 0 then fails += 1 end
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
