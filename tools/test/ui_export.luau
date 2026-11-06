--!nocheck
-- 界面导出：开服、进一个玩家，在几个场合把 PlayerGui 存下来（写成 JS 文件，给 ui_view.html 画出来看排版）
--   场合：刚进服（每日奖励）、基地（钱多了、盖了楼）、任务面板、建筑升级面板、布阵、打仗、开车选单、结算
-- 用法：lune run ui_export.luau <rbxlx> <输出.js> [pc|phone]
--   phone：触屏、没有键盘，屏幕 844 × 390（iPhone 横屏的逻辑像素）
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local H = require("./harness")
H.quietWarn = true

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
H.run(2)

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
	UITextSizeConstraint = true, UISizeConstraint = true, UIAspectRatioConstraint = true,
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

local function node(inst)
	local n = { c = inst.ClassName, n = inst.Name, p = {}, k = {} }
	for _, prop in PROPS do
		local ok, v = pcall(function() return inst[prop] end)
		if ok and v ~= nil then
			local s = ser(v)
			if s ~= nil then n.p[prop] = s end
		end
	end
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

local function act(...)
	local a = table.pack(...)
	local co = coroutine.create(function() H.Gs[pl.Name].R.Action:FireServer(table.unpack(a, 1, a.n)) end)
	H.ctx = pl
	coroutine.resume(co)
	H.ctx = nil
end
local function tryClick(pattern)
	local b = H.findButton(pl, pattern)
	if b then H.press(pl, b) end
	return b ~= nil
end

---------------------------------------------------------------- 场合

pl = H.addPlayer("P1", 8001)
H.run(8)
snap("join")
tryClick("^领取")
H.run(2)

local G = H.Gs.server
local st = G.states[pl]
st.data.cash = 2e6
local plotF = H.workspace.Plots["Plot" .. st.plot.index]
for _ = 1, 8 do
	for _, b in G.Config.Buildings do
		local m = plotF.Pads:FindFirstChild("Pad_" .. b.id)
		if m and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then H.ev(m.Pad, "Touched"):Fire(pl.Character.HumanoidRootPart) end
	end
	H.run(1.3)
end
H.run(4)
snap("base")

tryClick("^任务$")
H.run(0.5)
snap("missions")
tryClick("^×$")
H.run(0.5)
tryClick("^建筑$")
H.run(0.5)
snap("build")
tryClick("^×$")
H.run(0.5)

for _, t in { "tank", "tank", "ifv", "aa", "inf", "inf", "medic", "arty", "heli" } do
	act("buy", t)
	H.run(0.3)
end
H.run(15)
tryClick("^布阵$")
H.run(2)
snap("deploy")

tryClick("开战")
H.run(8)
snap("battle")
tryClick("开车")
H.run(0.5)
snap("drive")
tryClick("^×$")
H.run(0.5)

H.runUntil(function() return st.battle == nil end, 260)
H.run(4)
snap("result")

local js = "window.UI_SNAPS = Object.assign(window.UI_SNAPS || {}, " .. serde.encode("json", snaps) .. ");\n"
fs.writeFile(process.args[2], js)
H.summary()
print("写好了 " .. process.args[2])
