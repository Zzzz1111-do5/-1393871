--!nocheck
-- 在载入的发布包中检查战况、简报和步兵触控的实际 GUI 边界。
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V2 = roblox.Vector2

H.quietWarn = true
H.boot(process.args[1], {
	ds = "mock",
	before = function(game)
		local world = game:GetService("ServerScriptService").Main.World
		local source, count = world.Source:gsub("\nreturn World%s*$", "\nWorld.terrain = function() return 0, 0 end\nreturn World\n")
		assert(count == 1, "UI 测试应只跳过体素生成")
		world.Source = source
	end,
})
H.run(0.5)
local server = H.Gs.server
server.Config.Bots.minPerTeam = 0
server.fortsHold = true
server.navyNoAI = true
assert(H.runUntil(function() return server.worldReady end, 30), "场景可用")

local pc = H.addPlayer("Desktop", 8711)
H.run(1.5)
H.UIS.TouchEnabled, H.UIS.KeyboardEnabled = true, false
local camera = H.workspace.CurrentCamera
camera.ViewportSize = V2.new(844, 390)
local phone = H.addPlayer("Touch", 8712)
H.run(1.5)

local function inPlayer(player, fn)
	local old = H.ctx
	H.ctx = player
	local ok, err = coroutine.resume(coroutine.create(fn))
	H.ctx = old
	assert(ok, err)
end

for _, player in { pc, phone } do
	local client = H.Gs[player.Name]
	local side = server.P[player].team
	inPlayer(player, function()
		client.menuEnter()
		client.R.Act:FireServer("pickTeam", side)
	end)
	H.run(0.25)
	inPlayer(player, function()
		client.R.Act:FireServer("deploy", "rifle", side == "atk" and "fleet" or "camp")
	end)
end
assert(H.runUntil(function() return server.round.phase == "battle" end, 45), "回合开战")
H.run(0.5)

local function rect(gui)
	local v, s, p, a = camera.ViewportSize, gui.Size, gui.Position, gui.AnchorPoint
	local w, h = v.X * s.X.Scale + s.X.Offset, v.Y * s.Y.Scale + s.Y.Offset
	local x = v.X * p.X.Scale + p.X.Offset - a.X * w
	local y = v.Y * p.Y.Scale + p.Y.Offset - a.Y * h
	return { left = x, top = y, right = x + w, bottom = y + h }
end

local function overlaps(a, b)
	return a.left < b.right and a.right > b.left and a.top < b.bottom and a.bottom > b.top
end

local function contained(box)
	return box.left >= 0 and box.top >= 0 and box.right <= camera.ViewportSize.X and box.bottom <= camera.ViewportSize.Y
end

local function checkHud(client, player)
	assert(client.S.alive, player.Name .. " 已部署")
	local score = player.PlayerGui.Main.ScoreBar
	local briefing = player.PlayerGui.Main.OperationBrief
	local radar = player.PlayerGui:FindFirstChild("Radar", true)
	assert(score.Visible and briefing.Visible and radar, player.Name .. " 战况与第一阶段简报可见")
	assert(contained(rect(score)) and contained(rect(briefing)), player.Name .. " 战况与简报在画面内")
	assert(not overlaps(rect(score), rect(radar)) and not overlaps(rect(briefing), rect(radar)), player.Name .. " 战况与简报避开雷达")
	assert(not overlaps(rect(score), rect(briefing)), player.Name .. " 简报避开比分")
	return score, briefing
end

local pcClient, touchClient = H.Gs.Desktop, H.Gs.Touch
camera.ViewportSize = V2.new(820, 600)
H.run(0.12)
checkHud(pcClient, pc)

local controls = phone.PlayerGui.Main.Hud.InfantryTouch
for _, viewport in { V2.new(844, 390), V2.new(680, 320), V2.new(390, 844) } do
	camera.ViewportSize = viewport
	H.run(0.12)
	local score, briefing = checkHud(touchClient, phone)
	assert(controls.Visible and not controls.Support.Visible, "步兵触控区可见，支援键按装备出现")
	assert(briefing.Route.Visible == (viewport.Y >= 360), "窄横屏收起路线")
	local seen = {}
	for _, name in { "Fire", "Aim", "Reload", "Swap", "NightVision", "Tablet" } do
		local button = controls[name]
		local area = rect(button)
		assert(contained(area) and button.Size.Y.Offset >= 44, name .. " 在屏幕内且可点")
		assert(not overlaps(area, rect(briefing)) and not overlaps(area, rect(score)), name .. " 避开简报与比分")
		for _, other in seen do assert(not overlaps(area, other), name .. " 避开其他触控键") end
		table.insert(seen, area)
	end
	print(string.format("通过触控和 HUD 布局 %d×%d", viewport.X, viewport.Y))
end

touchClient.lang = "zh"
H.run(0.12)
assert(controls.Reload.Text == "换弹", "触控键随语言更新")
local nv = touchClient.nvgOn()
inPlayer(phone, function() H.press(phone, controls.NightVision) end)
H.run(0.12)
assert(touchClient.nvgOn() ~= nv, "触控夜视仍绑定实际入口")
inPlayer(phone, function() H.press(phone, controls.Aim) end)
H.run(0.12)
assert(touchClient.fpsAiming and not phone.PlayerGui.Main.OperationBrief.Visible, "瞄准时简报让位")
inPlayer(phone, function() H.press(phone, controls.Aim) end)
H.run(0.12)
assert(phone.PlayerGui.Main.OperationBrief.Visible, "松开瞄准恢复简报")

local oldDrive = touchClient.drive
touchClient.drive = {}
inPlayer(phone, function() touchClient.stepPlay(1 / 60) end)
assert(not controls.Visible, "上车后步兵触控让位")
touchClient.drive = oldDrive

H.summary()
assert(#H.errors == 0, table.concat(H.errors, "\n"))
print("布局回归全部通过")
