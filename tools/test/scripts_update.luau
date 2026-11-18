--!nocheck
-- 「只换脚本」的更新包（tools/build.luau 写的 ScriptsUpdate.rbxmx）和导入说明里那一行命令能不能用：
--   旧地点（脚本是旧的、ServerStorage / Workspace 里有导入的模型）→ 插入更新包到 ServerStorage → 原样跑 docs/import_guide.txt「三、只换脚本」里的命令
-- 用法（仓库根目录，先 lune run tools/build.luau）：lune run tools/test/scripts_update.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local game = roblox.deserializePlace(fs.readFile("RobloxTotalBattlefield.rbxlx"))
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
-- 旧版本：脚本内容是旧的；ServerStorage 里有用户导入的模型；Workspace 里还有没收起来的导入零件
RS.Config.Source = "-- 旧的 Config"
game:GetService("ServerScriptService").Main.Source = "-- 旧的 Main"
local im = roblox.Instance.new("Folder") im.Name = "ImportedModels" im.Parent = SS
local p = roblox.Instance.new("MeshPart") p.Name = "V_m1a2dc__Body_1" p.Parent = im
local w = roblox.Instance.new("MeshPart") w.Name = "A_j20_v3__Body_1" w.Parent = game:GetService("Workspace")
-- 用户「从文件插入」到 ServerStorage
local list = roblox.deserializeModel(fs.readFile("ScriptsUpdate.rbxmx"))
for _, x in list do x.Parent = SS end
-- 命令栏那一行（原样跑）
local env = setmetatable({ game = game, workspace = game:GetService("Workspace"), print = print, assert = assert, pairs = pairs, ipairs = ipairs }, { __index = _G })
-- 命令从导入说明里取（说明改了、命令写错了，这里就过不去）
local cmd = nil
for line in string.gmatch(fs.readFile("docs/import_guide.txt"), "[^\n]+") do
	if string.find(line, 'local u=game:GetService("ServerStorage"):FindFirstChild("ScriptsUpdate")', 1, true) == 1 then cmd = line end
end
assert(cmd, "导入说明里没找到「只换脚本」的命令")
luau.load(cmd, { environment = env })()
-- 检查
local ok = 0
local function check(c, what) print((c and "  通过 " or "  不对 ") .. what) if c then ok += 1 end end
check(RS.Config.Source == fs.readFile("src/ReplicatedStorage/Config.lua"), "Config 换成了新的")
check(game:GetService("ServerScriptService").Main.Source == fs.readFile("src/ServerScriptService/Main/init.server.lua"), "服务器主脚本换成了新的")
check(game:GetService("ServerScriptService").Main:FindFirstChild("Air") ~= nil and game:GetService("ServerScriptService").Main.Air.Source == fs.readFile("src/ServerScriptService/Main/Air.lua"), "服务器子模块也是新的")
local cl = game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts"):FindFirstChild("Client")
check(cl ~= nil and cl.ClassName == "LocalScript" and cl:FindFirstChild("Fly") ~= nil and cl.Fly.Source == fs.readFile("src/StarterPlayer/StarterPlayerScripts/Client/Fly.lua"), "客户端脚本（含 Fly）是新的")
check(RS:FindFirstChild("HitSurf") ~= nil, "新加的模块 HitSurf 也放进去了")
local nCfg = 0 for _, c in RS:GetChildren() do if c.Name == "Config" then nCfg += 1 end end
check(nCfg == 1, "没有重复的 Config")
check(SS:FindFirstChild("ImportedModels") and SS.ImportedModels:FindFirstChild("V_m1a2dc__Body_1") ~= nil, "ServerStorage 里导入的模型还在")
check(game:GetService("Workspace"):FindFirstChild("A_j20_v3__Body_1") ~= nil, "Workspace 里的导入零件还在")
check(SS:FindFirstChild("ScriptsUpdate") == nil, "更新包用完删掉了")
print(ok == 9 and "全部通过" or ("不对 " .. (9 - ok) .. " 处"))
