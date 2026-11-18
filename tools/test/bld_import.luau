--!nocheck
-- 地图建筑：导入了原模型时的那条路（World.lua building 用 Imported.Bld 的网格 + 看不见的碰撞盒）
--   lune run tools/test/bld_import.luau <rbxlx>：往地图文件的 ServerStorage 里塞一套假的 B_<键>__Body_<号>（按 BuildingMeta 的块），开服，
--   检查：每座建筑都换成了原模型（属性 Imported）、块数对、摆的位置在占地里、碰撞盒挡人挡子弹（CanCollide / CanQuery）、原模型的块不碰撞
local process = require("@lune/process")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local H = require("./harness")
H.quietWarn = true
local src = process.args[1]
local place = roblox.deserializePlace(fs.readFile(src))
local BM = luau.load(fs.readFile("src/ReplicatedStorage/BuildingMeta.lua"), { debugName = "BuildingMeta" })()
local SS = place:GetService("ServerStorage")
local holder = roblox.Instance.new("Model")
holder.Name = "BldFake"
local nParts = 0
for key, info in pairs(BM) do
	for name, p in pairs(info.parts) do
		local mp = roblox.Instance.new("Part")
		mp.Name = "B_" .. key .. "__" .. name
		mp.Size = roblox.Vector3.new(p.s[1], p.s[2], p.s[3])
		mp.Anchored = true
		mp.CFrame = roblox.CFrame.new()
		mp.Parent = holder
		nParts += 1
	end
end
holder.Parent = SS
local tmp = "/tmp/bld_import_test.rbxlx"
fs.writeFile(tmp, roblox.serializePlace(place))
H.boot(tmp, { ds = "mock" })
local G
for _ = 1, 30 * 120 do
	H.step(1 / 30)
	G = G or H.Gs.server
	if G and G.worldReady then break end
end
local fails = 0
local function check(ok, msg)
	print((ok and "  通过 " or "  不对 ") .. msg)
	if not ok then fails += 1 end
end
print(string.format("塞了 %d 块假的原模型零件（%d 种建筑）", nParts, (function() local n = 0 for _ in pairs(BM) do n += 1 end return n end)()))
local total, imported, badCount, badPlace, badColl = 0, 0, {}, {}, 0
for _, d in ipairs(H.workspace:GetDescendants()) do
	if d:IsA("Model") and d:GetAttribute("Bld") then
		total += 1
		local key = d:GetAttribute("Bld")
		if d:GetAttribute("Imported") then imported += 1 end
		local info = BM[key]
		local want = 0
		for _ in pairs(info.parts) do want += 1 end
		local mesh, coll = 0, 0
		local cx, cz, n = 0, 0, 0
		for _, p in ipairs(d:GetChildren()) do
			if p:IsA("BasePart") then
				if string.match(p.Name, "^B_") then
					mesh += 1
					if p.CanCollide or p.CanQuery then badColl += 1 end
					cx += p.CFrame.Position.X; cz += p.CFrame.Position.Z; n += 1
				elseif p.Name == "Collision" then
					coll += 1
					if not (p.CanCollide and p.CanQuery and p.Transparency >= 0.99) then badColl += 1 end
				end
			end
		end
		if mesh ~= want or coll == 0 then table.insert(badCount, key .. " " .. mesh .. "/" .. want .. " 碰撞盒 " .. coll) end
		-- 块的平均位置离碰撞盒中心不远（没有摆到别处去）
		local box = d:FindFirstChild("Collision")
		if box and n > 0 then
			local bp = box.CFrame.Position
			local dx, dz = cx / n - bp.X, cz / n - bp.Z
			if math.sqrt(dx * dx + dz * dz) > math.max(info.w, info.d) then table.insert(badPlace, key) end
		end
	end
end
check(total >= 30, "地图上摆了 " .. total .. " 座建筑")
check(imported == total, "都换成了原模型（" .. imported .. " / " .. total .. "）")
check(#badCount == 0, "每座的块数对、都有碰撞盒" .. ((#badCount > 0) and ("：" .. table.concat(badCount, "，")) or ""))
check(#badPlace == 0, "原模型的块摆在自己的占地上" .. ((#badPlace > 0) and ("：" .. table.concat(badPlace, "，")) or ""))
check(badColl == 0, "原模型的块不碰撞、碰撞盒看不见但挡人挡子弹（不对的 " .. badColl .. " 块）")
-- 碰撞盒挡射线：从港口镇一座房子正前方往里打一条水平射线
local hit = nil
for _, d in ipairs(H.workspace:GetDescendants()) do
	if d:IsA("Model") and d:GetAttribute("Bld") == "jph1" then
		local box = d:FindFirstChild("Collision")
		if box then
			local o = box.CFrame.Position + box.CFrame.LookVector * -(box.Size.Z / 2 + 20)
			hit = H.workspace:Raycast(o, box.CFrame.LookVector * 40)
		end
		break
	end
end
check(hit ~= nil and hit.Instance and hit.Instance.Name == "Collision", "子弹打得到房子（射线撞上碰撞盒：" .. tostring(hit and hit.Instance and hit.Instance.Name) .. "）")
print(string.format("脚本报错 %d 条", #H.errors))
for _, e in ipairs(H.errors) do print("  " .. tostring(e)) end
print(fails == 0 and #H.errors == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
