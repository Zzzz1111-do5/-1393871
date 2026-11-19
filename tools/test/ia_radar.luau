--!nocheck
-- 雷达测试（Hud.lua 右上的方形小地图，正常的地图颜色；没有转圈的扫描线）：友军都显示；敌方步兵在视线里才显示（太远、躲在墙后都不显示）；
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
	-- 用户 11-19：小地图不要黑绿，改成正常的——地图用「mini」配色（蓝海），框是白边，不是雷达绿
	check(CA.mapThemeNow and CA.mapThemeNow() == "mini", "小地图是正常的地图颜色（mini 配色）：" .. tostring(CA.mapThemeNow and CA.mapThemeNow()))
	local root = CA.mapRoot
	local sea = root and root.BackgroundColor3
	check(sea ~= nil and sea.B > sea.G and sea.G > sea.R and sea.B < 0.35, string.format("海是暗的深蓝（%d, %d, %d）", sea and sea.R * 255 or -1, sea and sea.G * 255 or -1, sea and sea.B * 255 or -1))
	-- 卫星图（MapPaint：用户 11-19 小地图更精细、更暗淡、更拟真）：测试台没有 EditableImage，直接算几个像素看颜色对不对
	local RS = H.game:GetService("ReplicatedStorage")
	local Paint = H.require(RS:FindFirstChild("MapPaint"))
	local Map = G.Map
	local function px(x, z, detail)
		local buf = buffer.create(3 * 4)
		Paint.paint(Map, { x0 = x - 9, z0 = z - 3, step = 6, w = 3, h = 1, detail = detail }, 0, 1, buf)
		return buffer.readu8(buf, 4), buffer.readu8(buf, 5), buffer.readu8(buf, 6)
	end
	local K = Map.K
	local deepX, deepZ = nil, nil   -- 找一处深海（水深 60 格以上，周围 800 格都是海）
	for _, c in ipairs({ { -8200, 0 }, { 8200, 0 }, { -8200, 6000 }, { 8200, 6000 }, { 0, 5200 }, { -6000, -7000 }, { 6000, -7000 } }) do
		if not deepX and Map.height(c[1], c[2]) < -60 and not Paint.hasLand(Map, c[1], c[2], 800) then deepX, deepZ = c[1], c[2] end
	end
	check(deepX ~= nil, "找到一处深海：" .. tostring(deepX) .. ", " .. tostring(deepZ))
	local r1, g1, b1 = px(deepX or 0, deepZ or 0, false)
	check(b1 > g1 and g1 > r1 and b1 < 70, string.format("深海：暗的深蓝（%d, %d, %d）", r1, g1, b1))
	local A = Map.AIRFIELD
	local r2, g2, b2 = px(A.x, A.z, true)
	check(math.abs(r2 - g2) < 10 and math.abs(g2 - b2) < 10 and r2 < 80, string.format("跑道：暗灰的沥青（%d, %d, %d）", r2, g2, b2))
	local gx, gz = Map.MAIN.x - 500 * K, Map.ridgeZ(Map.MAIN.x - 500 * K) + 120 * K
	local r3, g3, b3 = px(gx, gz, true)
	check(Map.height(gx, gz) > 1 and g3 >= r3 - 20 and r3 + g3 + b3 < 3 * 170, string.format("主岛上的地：暗、偏绿或土色（%d, %d, %d）", r3, g3, b3))
	check(Paint.hasLand(Map, Map.MAIN.x - 400, Map.MAIN.z - 400, 800) and deepX ~= nil, "细节块：主岛上要画，深海不画")
	check(CA.mapSatState ~= nil, "小地图有卫星图（测试台没有 EditableImage：退回色块）：" .. tostring(CA.mapSatState and CA.mapSatState()))
	local st = box:FindFirstChildOfClass("UIStroke")
	check(st ~= nil and st.Color.R > 0.85 and st.Color.G > 0.85, "框是白边（不是绿的）")
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
