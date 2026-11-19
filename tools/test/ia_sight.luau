--!nocheck
-- 坦克瞄准镜要第一人称（用户：坦克开镜要第一视角，不要第三）：守方每型坦克坐上去、右键开镜，查
--   ① 镜头在车里：离炮塔上的瞄准镜位置不到 0.6 格，在车体的长宽里面；朝着炮的方向
--   ② 自己的车整个藏起来：车模型里没有一块零件还看得见（LocalTransparencyModifier 没设成 1、本身也不透明的）
--   ③ 关镜：镜头回到车后面（第三人称），车又看得见
--   用法：lune run tools/test/ia_sight.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum
H.quietWarn = true
H.realProjection = true

H.boot(process.args[1], { ds = "mock" })
H.run(0.5)
local G = H.Gs.server
local cam = H.workspace.CurrentCamera
cam.ViewportSize = roblox.Vector2.new(1280, 720)
G.Config.Bots.minPerTeam = 0
for _, c in pairs(G.Config.VehicleCats) do c.cd, c.min, c.max = 0, 20, 20 end   -- 一型接一型地生成：不等冷却、不卡名额
H.runUntil(function() return G.worldReady end, 120)
local p1, p2 = H.addPlayer("P1", 8101), H.addPlayer("P2", 8102)
H.run(2)
local def = (G.P[p1].team == "def") and p1 or p2
H.removePlayer((def == p1) and p2 or p1)   -- 两个客户端共用一个镜头：另一个人别来摆镜头
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

local VD
as(def, function() VD = H.require(H.game:GetService("ReplicatedStorage"):FindFirstChild("VehDefs")) end)
-- 自己车模型里看得见的零件：本身不透明、本地也没藏
local function shown(v)
	local out = {}
	for _, p in v.model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 0.99 and p.LocalTransparencyModifier < 0.99 then table.insert(out, p) end
	end
	return out
end

-- 守方营地出生
act(def, "deploy", "rifle", "camp")
H.run(2)

local firedOnce = false
local list = {}
for _, cat in ipairs({ "tank", "apc", "aa", "arty" }) do
	for _, vid in ipairs(G.Config.Vehicles.def[cat]) do table.insert(list, vid) end
end
for _, vid in ipairs(list) do
	print("—— " .. vid)
	local tp = H.pad(G, vid)
	if not tp then print("    （没有生成点：地图自带的阵地，跳过）") continue end
	local e = tp and H.usePad(G, def, tp)
	if not e then
		print("    生成点 " .. tostring(tp ~= nil) .. "；车 " .. tostring(e ~= nil) .. "；在车上 " .. tostring(G.P[def].veh ~= nil))
	end
	if e then act(def, "enterVeh", e.id) end
	H.run(2)
	local st = CD.drive
	check(st ~= nil and st.d ~= nil and st.d.id == vid, "坐上了 " .. vid)
	if st and st.d then
		local d = st.d
		local v = CD.views and CD.views[st.em]
		-- 开镜（右键）
		H.mouseDown(def, 640, 360, Enum.UserInputType.MouseButton2)
		H.run(0.1)
		H.mouseUp(def, 640, 360, Enum.UserInputType.MouseButton2)
		H.run(0.8)
		check(st.sight == true, "右键开镜")
		local base = st.root * CF.new(0, -d.H / 2, 0)
		local tcf = VD.turretCF(d, base, st.ty)
		local gcf = VD.gunCF(d, base, st.ty, st.gp)
		local want = (tcf * CF.new(d.sight)).Position
		local cp = cam.CFrame.Position
		local loc = st.root:PointToObjectSpace(cp)
		print(string.format("    镜头在车里的位置 (%.2f, %.2f, %.2f)  车长 %.1f 宽 %.1f 高 %.1f", loc.X, loc.Y, loc.Z, d.L, d.W, d.H))
		check((cp - want).Magnitude < 0.6, string.format("镜头在瞄准镜上（差 %.2f 格）", (cp - want).Magnitude))
		check(math.abs(loc.X) < d.W / 2 and math.abs(loc.Z) < d.L / 2, "镜头在车体长宽里面（不是车后面的追尾镜头）")
		check(cam.CFrame.LookVector:Dot(gcf.LookVector) > 0.995, "镜头朝着炮")
		if v and v.model then
			local vis = shown(v)
			local names = {}
			for i = 1, math.min(#vis, 6) do names[i] = vis[i].Name end
			check(#vis == 0, "自己的车整个藏起来（看得见的零件 " .. #vis .. " 块" .. (#vis > 0 and ("：" .. table.concat(names, "、")) or "") .. "）")
		else
			check(false, "找到自己车的模型")
		end
		local box = def.PlayerGui:FindFirstChild("Radar", true)
		if d.cat == "tank" and not firedOnce then
			-- 用户：这个开镜为什么会透视地图——右上的小地图要整块在目镜黑框上面，不是透过镜片看到半块
			firedOnce = true
			check(box ~= nil and box.Parent ~= nil and box.Parent.Name == "RadarTop", "开着镜：小地图整块在目镜黑框上面")
			-- 用户：开火动画做的好一点——镜头后坐、镜里一阵炮口烟、炮管后坐，一两秒散掉
			H.mouseDown(def, 640, 360, Enum.UserInputType.MouseButton1)
			H.run(0.05)
			H.mouseUp(def, 640, 360, Enum.UserInputType.MouseButton1)
			H.run(0.12)
			local haze = def.PlayerGui:FindFirstChild("MuzzleHaze", true)
			check((st.kick or 0) > 0.4, string.format("开炮：镜头后坐（%.2f）", st.kick or 0))
			check(haze ~= nil and haze.BackgroundTransparency < 0.8, string.format("开炮：镜里一阵炮口烟（透明度 %.2f）", haze and haze.BackgroundTransparency or 1))
			check(v ~= nil and (v.recoil or 0) > 0.5, "开炮：炮管后坐")
			check(v ~= nil and math.abs(v.pitchV or 0) + math.abs(v.rollV or 0) > 0.2, "开炮：车体被后坐力推得一晃")
			H.run(2.5)
			check(haze ~= nil and haze.BackgroundTransparency > 0.97, "炮口烟一两秒散掉")
		end
		-- 关镜
		H.mouseDown(def, 640, 360, Enum.UserInputType.MouseButton2)
		H.run(0.1)
		H.mouseUp(def, 640, 360, Enum.UserInputType.MouseButton2)
		H.run(0.8)
		local back = st.root:PointToObjectSpace(cam.CFrame.Position)
		check(st.sight == false and back.Z > d.L / 2, string.format("关镜回到车后面（镜头在车后 %.1f 格）", back.Z - d.L / 2))
		if v and v.model then check(#shown(v) > 0, "关镜后车又看得见") end
		check(box ~= nil and box.Parent ~= nil and box.Parent.Name == "Hud", "关镜后小地图回到主界面")
		-- 下车，车拿掉（车位上停着车就不让再生成）
		H.key(def, Enum.KeyCode.F, true)
		H.run(0.1)
		H.key(def, Enum.KeyCode.F, false)
		H.run(1.5)
		if e then
			e.alive = false
			G.removeEnt(e)
		end
		H.run(0.5)
	end
end

print(fails == 0 and "坦克瞄准镜：全部通过" or ("坦克瞄准镜：" .. fails .. " 项没过"))
H.shutdown()
process.exit(fails == 0 and 0 or 1)
