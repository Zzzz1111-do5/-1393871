--!nocheck
-- 把 src/ 下的脚本拼成一个能直接用 Roblox Studio 打开的 MilitaryTycoon.rbxlx（和 Rojo 的目录约定一样）：
--   src/<服务名>/... ；目录 = Folder；X.lua = ModuleScript；X.server.lua = Script；X.client.lua = LocalScript；
--   目录里有 init.server.lua / init.client.lua / init.lua 时，这个目录本身就是那个脚本，其余文件是它的子模块
-- 用法（仓库根目录）：lune run tools/build.luau [输出文件，默认 MilitaryTycoon.rbxlx]
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local process = require("@lune/process")

local Instance = roblox.Instance
local out = process.args[1] or "MilitaryTycoon.rbxlx"

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
L.ClockTime = 14.6
L.Brightness = 3
L.GlobalShadows = true
L.EnvironmentDiffuseScale = 1
L.EnvironmentSpecularScale = 1

-- Lune 把 Source 写成 <string>，Studio 认的是 <ProtectedString>：逐个改过来（CDATA 里的内容不动）
local xml = roblox.serializePlace(game, true)
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
xml = table.concat(parts)
fs.writeFile(out, xml)
print("Source 改成 ProtectedString：" .. fixed .. " 处")
print(string.format("写好了 %s：Script %d、LocalScript %d、ModuleScript %d、Folder %d", out, count.Script, count.LocalScript, count.ModuleScript, count.Folder))
