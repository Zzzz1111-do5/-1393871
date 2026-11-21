--!nocheck
-- 把 src/ 下的脚本拼成一个能直接用 Roblox Studio 打开的 RobloxTotalBattlefield.rbxlx（和 Rojo 的目录约定一样）：
--   src/<服务名>/... ；目录 = Folder；X.lua = ModuleScript；X.server.lua = Script；X.client.lua = LocalScript；
--   目录里有 init.server.lua / init.client.lua / init.lua 时，这个目录本身就是那个脚本，其余文件是它的子模块
-- 用法（仓库根目录）：lune run tools/build.luau [输出文件，默认 RobloxTotalBattlefield.rbxlx]
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local process = require("@lune/process")

local Instance = roblox.Instance
local out = process.args[1] or "RobloxTotalBattlefield.rbxlx"

local game = Instance.new("DataModel")
local count = { Script = 0, LocalScript = 0, ModuleScript = 0, Folder = 0 }

local function kindOf(file)
	if file:match("%.server%.lua$") then return "Script", file:gsub("%.server%.lua$", "") end
	if file:match("%.client%.lua$") then return "LocalScript", file:gsub("%.client%.lua$", "") end
	if file:match("%.lua$") then return "ModuleScript", file:gsub("%.lua$", "") end
	return nil
end

local function sorted(list)
	table.sort(list)
	return list
end

local function build(dir, parent)
	for _, name in sorted(fs.readDir(dir)) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			local inst
			for _, init in { "init.server.lua", "init.client.lua", "init.lua" } do
				if fs.isFile(path .. "/" .. init) then
					local cls = kindOf(init)
					inst = Instance.new(cls)
					inst.Source = fs.readFile(path .. "/" .. init)
					count[cls] += 1
					break
				end
			end
			if not inst then
				-- StarterPlayer 下面这两个是专门的类（不能是普通 Folder，不然脚本不会被复制给玩家）
				local special = (name == "StarterPlayerScripts" or name == "StarterCharacterScripts") and parent.ClassName == "StarterPlayer"
				inst = parent:FindFirstChild(name) or Instance.new(special and name or "Folder")
				if not special then count.Folder += 1 end
			end
			inst.Name = name
			inst.Parent = parent
			build(path, inst)
		elseif not name:match("^init%.") then
			local cls, base = kindOf(name)
			if cls then
				local s = Instance.new(cls)
				s.Name = base
				s.Source = fs.readFile(path)
				s.Parent = parent
				count[cls] += 1
			end
		end
	end
end

for _, svcName in sorted(fs.readDir("src")) do
	local svc = game:GetService(svcName)
	build("src/" .. svcName, svc)
end

-- 在 Studio 里导入过一次的原模型（用户把导入的 MeshPart 收进一个文件夹、右键「保存到文件」存成 models/imported/*.rbxm / *.rbxmx）：
--   放进 ServerStorage.ImportedModels，开服时 Imports.lua 按名字收进 ReplicatedStorage.Imported——以后每个版本的地图文件都带着，不用再导一遍
local nImported = 0
if fs.isDir("models/imported") then
	local holder = Instance.new("Folder")
	holder.Name = "ImportedModels"
	for _, name in sorted(fs.readDir("models/imported")) do
		if name:match("%.rbxmx?$") then
			local ok, list = pcall(roblox.deserializeModel, fs.readFile("models/imported/" .. name))
			if ok then
				for _, inst in list do
					inst.Parent = holder
					for _, d in inst:GetDescendants() do
						if d:IsA("BasePart") then nImported += 1 end
					end
					if inst:IsA("BasePart") then nImported += 1 end
				end
			else
				print("读不了 models/imported/" .. name .. "：" .. tostring(list))
			end
		end
	end
	if nImported > 0 then holder.Parent = game:GetService("ServerStorage") end
end

-- 不是脚本的东西：放导入模型的文件夹、关掉流式加载（客户端要复制服务器的单位模型）
local rs = game:GetService("ReplicatedStorage")
if not rs:FindFirstChild("UnitModels") then
	local f = Instance.new("Folder")
	f.Name = "UnitModels"
	f.Parent = rs
end
local ws = game:GetService("Workspace")
ws.StreamingEnabled = false
-- 光照：Future（脚本里改不了，只能写进地图文件）；其余的开服时 Scenery.lighting 还会再设一遍
local L = game:GetService("Lighting")
L.Technology = roblox.Enum.Technology.Future
L.ClockTime = 2.3   -- 夜战（开服时 World.lighting 还会再设一遍）
L.Brightness = 2.2
L.GlobalShadows = true
L.EnvironmentDiffuseScale = 1
L.EnvironmentSpecularScale = 1

-- Lune 把 Source 写成 <string>，Studio 认的是 <ProtectedString>：逐个改过来（CDATA 里的内容不动）
local function protectSource(xml)
	local parts, pos, fixed = {}, 1, 0
	while true do
		local a, b = string.find(xml, '<string name="Source">', pos, true)
		if not a then break end
		table.insert(parts, string.sub(xml, pos, a - 1))
		table.insert(parts, '<ProtectedString name="Source">')
		local i = b + 1
		while true do
			if string.sub(xml, i, i + 8) == "<![CDATA[" then
				local e = string.find(xml, "]]>", i + 9, true)
				table.insert(parts, string.sub(xml, i, e + 2))
				i = e + 3
			elseif string.sub(xml, i, i + 8) == "</string>" then
				table.insert(parts, "</ProtectedString>")
				i += 9
				break
			else
				local nxt = string.find(xml, "<", i, true)
				table.insert(parts, string.sub(xml, i, nxt - 1))
				i = nxt
			end
		end
		fixed += 1
		pos = i
	end
	table.insert(parts, string.sub(xml, pos))
	return table.concat(parts), fixed
end
local xml, fixed = protectSource(roblox.serializePlace(game, true))
fs.writeFile(out, xml)
print("Source 改成 ProtectedString：" .. fixed .. " 处")
print(string.format("写好了 %s：Script %d、LocalScript %d、ModuleScript %d、Folder %d", out, count.Script, count.LocalScript, count.ModuleScript, count.Folder))
if nImported > 0 then print("带上了 models/imported 里导入过的原模型：" .. nImported .. " 块") end

-- 只换脚本的更新包（用户：怎么才能只改脚本）：ScriptsUpdate.rbxmx，一个 ScriptsUpdate 文件夹，里面按服务分好
--   ReplicatedStorage / ServerScriptService / StarterPlayerScripts 三个子文件夹，装着 src/ 里全部脚本。用户在自己的地点（导入过的模型、地图都在）
--   里「从文件插入」它，再在命令栏粘一行（docs/import_guide.txt「三、只换脚本」）：同名的旧脚本删掉、新的放进去，模型和地图不动
local count0 = table.clone(count)
local pack = Instance.new("Folder")
pack.Name = "ScriptsUpdate"
for _, svcName in sorted(fs.readDir("src")) do
	local f = Instance.new("Folder")
	if svcName == "StarterPlayer" then
		f.Name = "StarterPlayerScripts"
		build("src/StarterPlayer/StarterPlayerScripts", f)
	else
		f.Name = svcName
		build("src/" .. svcName, f)
	end
	f.Parent = pack
end
count = count0
local packXml = protectSource(roblox.serializeModel({ pack }, true))
local packOut = string.gsub(out, "[^/\\]+$", "ScriptsUpdate.rbxmx")
fs.writeFile(packOut, packXml)
print("写好了 " .. packOut .. "（只换脚本的更新包）")
