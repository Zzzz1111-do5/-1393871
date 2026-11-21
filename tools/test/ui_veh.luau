--!nocheck
-- 载具界面导出（照 ui_export.luau，只拍载具）：坦克追尾视角 tank、坦克开炮那一下 tank_fire、MWT 式准星 tank_pen / tank_mg、坦克瞄准镜 tank_sight、
--   舰艇 ship、《现代战舰》式准星 ship_lead / ship_locking / ship_locked
--   用法：lune run tools/test/ui_veh.luau <rbxlx> <输出.js> [pc|phone]
--   截图：NODE_PATH=$(npm root -g) node tools/test/ui_shot.cjs <放 ui_pc.js 的目录> <输出目录> pc_tank pc_tank_sight … [--bg 背景图]
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum
local Color3 = roblox.Color3
H.quietWarn = true
local MOON = V3.new(0.35, 0.42, -0.84).Unit
pcall(function() roblox.implementMethod("Lighting", "GetMoonDirection", function() return MOON end) end)
H.realProjection = true   -- 截图要看画在投影点上的东西（瞄准镜的眩光等）：测试台换成真的透视投影

local dev = process.args[3] or "pc"
local VW, VH = 1280, 720
if dev == "phone" then VW, VH = 844, 390 end
H.boot(process.args[1], { ds = "mock" })
H.workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(VW, VH)
if dev == "phone" then
	H.UIS.TouchEnabled = true
	H.UIS.KeyboardEnabled = false
	H.UIS.MouseEnabled = false
end

---------------------------------------------------------------- 存 GUI 树

local PROPS = {
	"Visible", "Position", "Size", "AnchorPoint", "ZIndex", "LayoutOrder", "BackgroundColor3", "BackgroundTransparency", "BorderSizePixel",
	"AutomaticSize", "ClipsDescendants", "Rotation",
	"Text", "TextColor3", "TextSize", "TextScaled", "TextWrapped", "TextXAlignment", "TextYAlignment", "Font", "RichText", "TextTransparency",
	"TextStrokeTransparency", "TextStrokeColor3", "LineHeight",
	"CanvasSize", "CanvasPosition", "AutomaticCanvasSize", "ScrollBarThickness",
	"Enabled", "DisplayOrder", "IgnoreGuiInset",
	"CornerRadius", "Color", "Thickness", "Transparency", "ApplyStrokeMode", "Offset",
	"FillDirection", "Padding", "HorizontalAlignment", "VerticalAlignment", "SortOrder",
	"PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom", "Scale",
	"MaxTextSize", "MinTextSize", "MinSize", "MaxSize", "AspectRatio",
	"Image", "ImageColor3", "ImageTransparency",
	"CellSize", "CellPadding", "FillDirectionMaxCells", "StartCorner",
}
local KEEP = {
	ScreenGui = true, Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true,
	CanvasGroup = true, UICorner = true, UIStroke = true, UIGradient = true, UIListLayout = true, UIGridLayout = true, UIPadding = true, UIScale = true,
	UITextSizeConstraint = true, UISizeConstraint = true, UIAspectRatioConstraint = true, ViewportFrame = true,
}

local function ser(v)
	local t = typeof(v)
	if t == "UDim2" then return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } end
	if t == "UDim" then return { v.Scale, v.Offset } end
	if t == "Vector2" then
		local function fin(x) return (x ~= x or math.abs(x) > 1e8) and 1e8 or x end
		return { fin(v.X), fin(v.Y) }
	end
	if t == "Color3" then return { math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5) } end
	if t == "EnumItem" then return v.Name end
	if t == "ColorSequence" then
		local out = {}
		for _, k in v.Keypoints do
			table.insert(out, { k.Time, math.floor(k.Value.R * 255 + 0.5), math.floor(k.Value.G * 255 + 0.5), math.floor(k.Value.B * 255 + 0.5) })
		end
		return out
	end
	if t == "NumberSequence" then
		local out = {}
		for _, k in v.Keypoints do table.insert(out, { k.Time, k.Value }) end
		return out
	end
	if t == "boolean" or t == "number" or t == "string" then return v end
	return nil
end

local function r3(x) return math.floor(x * 1000 + 0.5) / 1000 end
-- ViewportFrame：零件换到镜头坐标（镜头朝 −Z），再除以 tan(半视角)——网页端按框的高度一半放大就是屏幕坐标
local function viewport(vp)
	-- 测试台（Lune）里读 ViewportFrame.CurrentCamera 会出错：挂载编辑器把镜头放在框里，直接找
	local okC, cam = pcall(function() return vp.CurrentCamera end)
	if not okC or not cam then cam = vp:FindFirstChildOfClass("Camera") end
	if not cam then return nil end
	local cinv = cam.CFrame:Inverse()
	local t = math.tan(math.rad(cam.FieldOfView) / 2)
	local parts = {}
	for _, p in vp:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 0.98 then
			local c = cinv * p.CFrame
			local kind = "box"
			if p.ClassName == "WedgePart" then kind = "wedge"
			elseif p:FindFirstChildOfClass("SpecialMesh") then kind = "ell"
			elseif p.Shape == Enum.PartType.Cylinder then kind = "cyl"
			elseif p.Shape == Enum.PartType.Ball then kind = "ball" end
			local _, _, _, a, b, cc, d, e, f, g, h, i = c:GetComponents()
			table.insert(parts, {
				k = kind, p = { r3(c.X), r3(c.Y), r3(c.Z) }, r = { r3(a), r3(b), r3(cc), r3(d), r3(e), r3(f), r3(g), r3(h), r3(i) },
				s = { r3(p.Size.X), r3(p.Size.Y), r3(p.Size.Z) }, c = ser(p.Color), t = r3(p.Transparency), n = (p.Material == Enum.Material.Neon) and 1 or nil,
			})
		end
	end
	local L = cinv:VectorToWorldSpace(vp.LightDirection.Unit)
	return { t = t, parts = parts, light = { r3(L.X), r3(L.Y), r3(L.Z) }, amb = ser(vp.Ambient), lc = ser(vp.LightColor) }
end

local function node(inst)
	local n = { c = inst.ClassName, n = inst.Name, p = {}, k = {} }
	for _, prop in PROPS do
		local ok, v = pcall(function() return inst[prop] end)
		if ok and v ~= nil then
			local s = ser(v)
			if s ~= nil then n.p[prop] = s end
		end
	end
	if inst.ClassName == "ViewportFrame" then n.vp = viewport(inst) end
	for _, ch in inst:GetChildren() do
		if KEEP[ch.ClassName] then table.insert(n.k, node(ch)) end
	end
	return n
end

local snaps = {}
local pl
local function snap(name)
	local pg = pl:FindFirstChildOfClass("PlayerGui")
	-- 测试台才有的报错红条（Lune 读不到零件的 Position 等）不进截图
	for _, d in pg:GetDescendants() do
		if d:IsA("TextLabel") and d.ZIndex == 50 and d.BackgroundColor3 == Color3.fromRGB(150, 30, 30) then d.Visible = false end
	end
	local guis = {}
	for _, g in pg:GetChildren() do
		if g.ClassName == "ScreenGui" then table.insert(guis, node(g)) end
	end
	snaps[dev .. "_" .. name] = { dev = dev, vw = VW, vh = VH, name = name, guis = guis }
	print("  存了 " .. dev .. "_" .. name)
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
local function tryClick(who, pattern)
	local b = H.findButton(who, pattern)
	if b then H.press(who, b) end
	return b ~= nil
end

---------------------------------------------------------------- 场合

H.run(0.5)
local G = H.Gs.server
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
G.Config.VehicleCats.ship.min = 2
H.runUntil(function() return G.worldReady end, 120)
local p1, p2 = H.addPlayer("P1", 8101), H.addPlayer("P2", 8102)
H.run(2)
local def = (G.P[p1].team == "def") and p1 or p2
local other = (def == p1) and p2 or p1
H.removePlayer(other)   -- 测试台里两个客户端共用一个镜头：另一个人（在主菜单）每帧也在摆镜头，拍载具前先让他走
H.run(0.5)
local PD = G.P[def]
local CD = H.Gs[def.Name]
pl = def
CD.lang = (dev == "pc") and "zh" or "en"
if CD.refresh then CD.refresh() end
H.run(0.3)

-- 坦克：守方营地出生，车场生成、坐上，往前开一会儿、炮塔转向侧面（看得出车体和炮塔的朝向不一样）
act(def, "deploy", "rifle", "camp")
H.run(2)
snap("foot_body")   -- 步行第一人称：记录仪观感（用户：持枪参考 bodycam）
local tankId = G.Config.Vehicles.def.tank[3]
local tp = H.pad(G, tankId)
local e = tp and H.usePad(G, def, tp)
if e then act(def, "enterVeh", e.id) end
H.run(2)
local st = CD.drive
if st then
	st.camYaw = st.camYaw + math.rad(35)   -- 镜头往左转一点：炮塔跟着转、车体不动
	st.camPitch = -0.08
	H.key(def, Enum.KeyCode.W, true)
	H.run(1.6)
	H.key(def, Enum.KeyCode.W, false)
	H.run(0.6)
	snap("tank")
	-- 开炮那一下：瞄准圈涨一下、装填环清零
	st.next = st.next or {}
	local wid = st.d.weapons[st.wi]
	if wid then
		H.mouseDown(def, 640, 360, Enum.UserInputType.MouseButton1)
		H.run(0.12)
		H.mouseUp(def, 640, 360, Enum.UserInputType.MouseButton1)
		snap("tank_fire")
		H.run(1.2)
		snap("tank_reload")
	end
	-- MWT 式准星：正前方 140 格放一辆攻方坦克——主炮正对着打（绿：可击穿），换机枪（红：打不穿）
	do
		local d0 = st.d
		local base0 = st.root * CF.new(0, -d0.H / 2, 0)
		local fwd = V3.new(-math.sin(st.camYaw), 0, -math.cos(st.camYaw))
		local fp = base0.Position + fwd * 140
		local foeT = G.spawnGroundVeh("atk", G.Config.Vehicles.atk.tank[1], CF.lookAt(fp, fp - fwd), false, nil)
		local function aimAt(pt)
			local rel = pt - H.workspace.CurrentCamera.CFrame.Position
			st.camYaw = math.atan2(-rel.X, -rel.Z)
			st.camPitch = math.asin(math.clamp(rel.Unit.Y, -1, 1))
		end
		if foeT then
			for _ = 1, 30 do aimAt(foeT.root.CFrame.Position) H.run(0.1) end
			snap("tank_pen")
			-- 换 12.7 毫米机枪打坦克：红「打不穿」
			H.key(def, Enum.KeyCode.Two, true)
			H.run(0.1)
			H.key(def, Enum.KeyCode.Two, false)
			for _ = 1, 8 do aimAt(foeT.root.CFrame.Position) H.run(0.1) end
			snap("tank_mg")
			H.key(def, Enum.KeyCode.One, true)
			H.run(0.1)
			H.key(def, Enum.KeyCode.One, false)
			G.removeEnt(foeT)
			H.run(0.5)
		end
	end
	H.mouseDown(def, 640, 360, Enum.UserInputType.MouseButton2)
	H.run(0.1)
	H.mouseUp(def, 640, 360, Enum.UserInputType.MouseButton2)
	H.run(0.6)
	snap("tank_sight")
	H.mouseDown(def, 640, 360, Enum.UserInputType.MouseButton2)
	H.run(0.1)
	H.mouseUp(def, 640, 360, Enum.UserInputType.MouseButton2)
	H.run(0.3)
	H.key(def, Enum.KeyCode.F, true)
	H.run(0.1)
	H.key(def, Enum.KeyCode.F, false)
	H.run(1.5)
else
	print("  没坐上坦克")
end

-- 舰艇：崖顶的终端柱生成 DDG-125，人直接上舰桥；车钟加两档往前开
local pd = H.pad(G, "ddg125")
local es = pd and H.usePad(G, def, pd)
H.run(2)
if es and CD.sail then
	H.key(def, Enum.KeyCode.W, true)
	H.run(0.1)
	H.key(def, Enum.KeyCode.W, false)
	H.run(0.2)
	H.key(def, Enum.KeyCode.W, true)
	H.run(0.1)
	H.key(def, Enum.KeyCode.W, false)
	H.key(def, Enum.KeyCode.A, true)
	H.run(2)
	snap("ship")
	H.key(def, Enum.KeyCode.A, false)
	-- 《现代战舰》式准星：前方 1300 格一艘攻方 022 横着开过去——落点大圈、目标卡、提前量；再换导弹：锁定中 → 已锁定
	local sst = CD.sail
	local sfwd = V3.new(-math.sin(sst.yaw), 0, -math.cos(sst.yaw))
	local sright = V3.new(-sfwd.Z, 0, sfwd.X)
	-- 先把船挪到外海（码头在崖下：镜头会钻进崖壁，准星打在镜头上）
	sst.pos = sst.pos + sfwd * 700
	sst.cf = CF.lookAt(sst.pos, sst.pos + sfwd)
	sst.speed, sst.order = 0, 0
	G.moveEnt(es, sst.cf * CF.new(0, es.sd.H / 2 - es.sd.draft, 0))
	es.lastSync, es.speed = os.clock(), 0
	H.run(1)
	local fp2 = es.root.CFrame.Position + sfwd * 1300
	local foeS = G.spawnShip("atk", "t022", CF.lookAt(V3.new(fp2.X, 0, fp2.Z), V3.new(fp2.X, 0, fp2.Z) + sright), nil)
	if foeS then
		local function aimShip()
			local tp = foeS.root.CFrame.Position
			local rel = tp - H.workspace.CurrentCamera.CFrame.Position
			sst.camYaw = math.atan2(-rel.X, -rel.Z)
			sst.camPitch = math.asin(math.clamp(rel.Unit.Y, -1, 1))
		end
		sst.order = 0
		for _ = 1, 50 do
			G.moveEnt(foeS, foeS.root.CFrame + sright * 4.5)   -- 每秒 45 格横穿
			aimShip()
			H.run(0.1)
		end
		snap("ship_lead")
		H.key(def, Enum.KeyCode.Two, true)
		H.run(0.1)
		H.key(def, Enum.KeyCode.Two, false)
		for _ = 1, 3 do G.moveEnt(foeS, foeS.root.CFrame + sright * 4.5) aimShip() H.run(0.1) end
		snap("ship_locking")
		for _ = 1, 8 do G.moveEnt(foeS, foeS.root.CFrame + sright * 4.5) aimShip() H.run(0.1) end
		snap("ship_locked")
		H.key(def, Enum.KeyCode.One, true)
		H.run(0.1)
		H.key(def, Enum.KeyCode.One, false)
		G.removeEnt(foeS)
	end
else
	print("  没上舰")
end

-- 飞机光电吊舱（用户给的 TGP 参考）：下舰，坐上守方的 F-35，P 进吊舱，V 切到白热，吊舱往下看
if CD.sail then
	H.key(def, Enum.KeyCode.F, true)
	H.run(0.1)
	H.key(def, Enum.KeyCode.F, false)
	H.run(1.5)
end
local jp = H.pad(G, "f35")
local ej = jp and H.usePad(G, def, jp)
-- 挂载编辑器：按「生成」
local goJ = H.findButton(def, "^" .. CD.T("pad.spawn") .. "$")
if goJ then H.press(def, goJ) end
H.run(1)
ej = nil
for _, e2 in ipairs(G.aircraft or {}) do
	if e2.alive and jp and e2.padId == jp.id then ej = e2 end
end
if ej then act(def, "enterVeh", ej.id) end
H.run(2)
if CD.fly and CD.fly.pilot then
	H.key(def, Enum.KeyCode.P, true)
	H.run(0.1)
	H.key(def, Enum.KeyCode.P, false)
	H.run(0.4)
	H.key(def, Enum.KeyCode.V, true)
	H.run(0.1)
	H.key(def, Enum.KeyCode.V, false)
	H.run(0.6)
	snap("jet_eo")
else
	print("  没坐上飞机")
end

local js = "window.UI_SNAPS = Object.assign(window.UI_SNAPS || {}, " .. serde.encode("json", snaps) .. ");\n"
fs.writeFile(process.args[2], js)
H.summary()
for _, w in ipairs(H.warns) do print(string.format("  警告 %.1f %s：%s", w.t, w.side, string.sub(w.msg, 1, 300))) end
print("写好了 " .. process.args[2])
