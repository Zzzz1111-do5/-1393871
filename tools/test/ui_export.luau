--!nocheck
-- 界面导出：开服、进两个玩家，在几个场合把 PlayerGui 存下来（写成 JS 文件，给 ui_view.html 画出来看排版）
--   场合：menu 主菜单 · faction 选阵营 · deploy_kit 部署的装备页 · deploy_pick 点开一格装备 · deploy 部署的生成点页 · hangar 挂载编辑器全景（航母甲板上的生成点按 E 弹出）· hangar_sel 选中挂点换弹 · fly 甲板上的歼-35 ·
--   fly_air 空中 · heli 直升机 · battle 步兵 · board 计分板 · scope 狙击镜开镜 · scope_kick 开枪那一下（镜内阴影） · scope_moon 狙击镜里有月亮（眩光） · binoc 望远镜 · result 结算
--   挂载编辑器的 ViewportFrame 里的零件按镜头投影存下来（ui_view.html 按面画成 3D，看白圈是不是对在挂点上）
-- 用法：lune run ui_export.luau <rbxlx> <输出.js> [pc|phone]
--   phone：触屏、没有键盘，屏幕 844 × 390（iPhone 横屏的逻辑像素）
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum
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
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)
local p1, p2 = H.addPlayer("P1", 8001), H.addPlayer("P2", 8002)
H.run(3)
local atk = (G.P[p1].team == "atk") and p1 or p2
local def = (atk == p1) and p2 or p1
pl = atk
local C = H.Gs[atk.Name]
local CD = H.Gs[def.Name]
local T = C.T
-- 电脑版看中文、手机版看英文（两种语言的排版都看到）
for _, X in ipairs({ C, CD }) do
	X.lang = (dev == "pc") and "zh" or "en"
	if X.refresh then X.refresh() end
end
H.run(0.3)

-- 选阵营（进服先看这个）
H.run(0.5)
snap("menu")
-- 选地图（主菜单「开始游戏」打开）：服务器已经在打岛的样子；再看一张还没定地图时的样子（三张都能点）
if C.showMapPick then
	as(atk, function() C.showMapPick() end)
	H.run(0.5)
	snap("mappick")
	local S2 = table.clone(C.S)
	S2.map, S2.mapReady = nil, false
	as(atk, function() C.refreshMapPick(S2) end)
	snap("mappick_new")
	local mp = atk:FindFirstChildOfClass("PlayerGui"):FindFirstChild("MapPick")
	if mp then mp.Enabled = false end
	H.run(0.3)
end
if C.menuEnter then
	local prev = H.ctx
	H.ctx = atk
	C.menuEnter()
	H.ctx = prev
end
H.run(0.3)
snap("faction")
act(atk, "pickTeam", "atk")
act(def, "pickTeam", "def")
H.run(0.6)

-- 部署：先看装备页，点开第 2 格（发射器）弹出能换的，再到生成点页
C.deploySel.pageUser = "kit"
C.refreshDeploy()
H.run(0.3)
snap("deploy_kit")
if C.deployPick then C.deployPick(2) end
C.refreshDeploy()
H.run(0.3)
snap("deploy_pick")
if C.deployPick then C.deployPick(2) end
C.deploySel.pageUser = nil
C.deploySel.role, C.deploySel.spawn = "rifle", "fleet"
C.refreshDeploy()
H.run(0.5)
snap("deploy")

-- 航母甲板出生，走到歼-35 的生成点按 E：弹出挂载编辑器
act(atk, "deploy", "rifle", "cv")
H.run(2)
local jp = H.pad(G, "j35")
if jp then H.usePad(G, atk, jp) end
H.run(1.2)
local HS = C.hangarState and C.hangarState()
snap("hangar")
if HS and HS.d then
	local hg = atk.PlayerGui:FindFirstChild("Hangar")
	local spot = nil
	for i, s in ipairs(HS.d.st) do
		local b = hg and hg:FindFirstChild("Spot" .. i, true)
		if s.name == "wingI" and b and b.Visible then spot = b end
	end
	if spot then H.press(atk, spot) end
	H.run(1.0)
	for _, b in ipairs(hg:GetDescendants()) do
		if b:IsA("TextButton") and H.visible(b) then
			for _, l in ipairs(b:GetChildren()) do
				if l:IsA("TextLabel") and l.Text == T("aw.lt2") then H.press(atk, b) end
			end
		end
	end
	H.run(0.6)
	snap("hangar_sel")
	tryClick(atk, "^" .. T("pad.spawn") .. "$")
	H.run(1)
end

-- 甲板上的歼-35：走过去坐上
for _, x in ipairs(G.aircraft) do
	if jp and x.padId == jp.id and x.alive then act(atk, "enterVeh", x.id) end
end
H.run(2.5)
snap("fly")

-- 空中：直接摆到 600 格高、200 格 / 秒（两边一起挪，不然服务器当成作弊拉回去）
local P = G.P[atk]
local e = P.vehicle
local st = C.fly
if e and st then
	H.run(0.1)
	local cf = CF.lookAt(V3.new(0, 600, 2600), V3.new(0, 600, 0))
	e.root.CFrame = cf
	e.lastSync = os.clock()
	e.vel = cf.LookVector * 200
	e.onGround = false
	st.cf = cf
	local look = cf.LookVector
	st.yaw = math.atan2(-look.X, -look.Z)
	st.spd, st.vel, st.hv = 200, look * 200, V3.new(look.X * 200, 0, look.Z * 200)
	st.ground, st.cat, st.trap, st.crashed = false, nil, nil, false
	st.aimYaw, st.aimPitch = st.yaw, 0
	st.gearWant = 0
	st.thr = 85
	H.run(1.5)
	snap("fly_air")
	H.key(atk, Enum.KeyCode.F, true)
	H.run(0.1)
	H.key(atk, Enum.KeyCode.F, false)
	H.run(1)
end

-- 直升机（守方营地出生，停机坪生成、坐上）
pl = def
act(def, "deploy", "rifle", "camp")
H.run(2)
local hp = H.pad(G, "ah64e")
if hp then
	H.usePad(G, def, hp)
	tryClick(def, "^" .. CD.T("pad.spawn") .. "$")
	H.run(1)
	for _, x in ipairs(G.aircraft) do
		if x.padId == hp.id and x.alive then act(def, "enterVeh", x.id) end
	end
end
H.run(3)
snap("heli")
H.key(def, Enum.KeyCode.F, true)
H.run(0.1)
H.key(def, Enum.KeyCode.F, false)
H.run(1)

-- 步兵（开战后）
local R = G.round
if R and R.phase == "prep" then R.prepEnds = 0 end
H.run(1)
pl = atk
if G.P[atk].alive and G.P[atk].vehicle == nil then
	-- 跳伞落海之后还活着就先这样
else
	H.runUntil(function() return (C.S and (C.S.wait or 0) <= 0 and not C.S.alive) end, 30)
	C.deploySel.mode = "inf"
	C.deploySel.role, C.deploySel.spawn = "rifle", "fleet"
	C.refreshDeploy()
	tryClick(atk, "^" .. T("ui.deployBtn") .. "$")
end
H.run(3)
snap("battle")
tryClick(atk, "^≡$")
H.run(0.5)
snap("board")
tryClick(atk, "^≡$")
H.run(0.3)

-- 狙击镜、望远镜：开镜后的圆形目镜和光学效果（换成狙击手发武器、按 1 拿狙击枪、按住右键）
--   测试台里两个客户端共用一个镜头：守方那边（还在直升机里）每帧也在改视角，先让它停一下，不然视角、分划（第一焦平面按视角摆）都不对
do
	local P = G.P[atk]
	local sp, sf = CD.stepPlay, CD.stepFly
	CD.stepPlay, CD.stepFly = function() end, function() end
	if P.alive and not P.vehicle then
		local cam = H.workspace.CurrentCamera
		local function aimAt(dir)
			local o = cam.CFrame.Position
			cam.CFrame = CF.lookAt(o, o + dir)
		end
		local function regive(role)   -- 手上拿着的那把先放回背包（客户端放下它），再按新兵种发（giveLoadout 只清背包）
			local bp = atk:FindFirstChildOfClass("Backpack")
			for _, c in ipairs(P.char:GetChildren()) do if c:IsA("Tool") then c.Parent = bp end end
			H.run(0.3)
			P.role = role
			G.giveLoadout(P)
		end
		regive("sniper")
		H.run(0.3)
		H.key(atk, Enum.KeyCode.One, true)
		H.key(atk, Enum.KeyCode.One, false)
		H.run(0.8)
		aimAt(V3.new(0.2, -0.05, -1).Unit)
		H.mouseDown(atk, 640, 360, Enum.UserInputType.MouseButton2)
		H.run(1.2)
		snap("scope")
		-- 开一枪：后坐把出瞳甩开，边上出现镜内阴影
		H.mouseDown(atk, 640, 360, Enum.UserInputType.MouseButton1)
		H.run(0.07)
		snap("scope_kick")
		H.mouseUp(atk, 640, 360, Enum.UserInputType.MouseButton1)
		H.run(0.8)
		-- 镜头偏一点对着月亮：眩光、鬼影
		local side = MOON:Cross(V3.new(0, 1, 0)).Unit
		aimAt((MOON + side * 0.09 - V3.new(0, 0.05, 0)).Unit)
		H.run(0.4)
		snap("scope_moon")
		H.mouseUp(atk, 640, 360, Enum.UserInputType.MouseButton2)
		H.run(0.3)
		regive("spotter")
		H.run(0.3)
		H.key(atk, Enum.KeyCode.Two, true)
		H.key(atk, Enum.KeyCode.Two, false)
		H.run(0.8)
		aimAt(V3.new(0.25, -0.12, -1).Unit)
		H.mouseDown(atk, 640, 360, Enum.UserInputType.MouseButton2)
		H.run(1.2)
		snap("binoc")
		H.mouseUp(atk, 640, 360, Enum.UserInputType.MouseButton2)
		H.run(0.3)
	end
	CD.stepPlay, CD.stepFly = sp, sf
end

-- 结算：时间到（没人在占点）
if R then
	R.endsAt = 0
	R.overtimeEnds = 0
end
H.run(2)
snap("result")

local js = "window.UI_SNAPS = Object.assign(window.UI_SNAPS || {}, " .. serde.encode("json", snaps) .. ");\n"
fs.writeFile(process.args[2], js)
H.summary()
for _, w in ipairs(H.warns) do print(string.format("  警告 %.1f %s：%s", w.t, w.side, string.sub(w.msg, 1, 300))) end
print("写好了 " .. process.args[2])
