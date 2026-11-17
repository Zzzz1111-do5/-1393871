--!nocheck
-- 宣传片用的模型元数据：ImportedMeta / ImportedAir / ImportedShip（Lua 表）转成一个 JSON（炮塔转轴、炮口、旋翼、尾喷口、舰炮……）
-- 用法（仓库根目录）：lune run tools/trailer/export_meta.luau <输出.json>
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local process = require("@lune/process")
local out = {}
for _, k in ipairs({ "ImportedMeta", "ImportedAir", "ImportedShip" }) do
	local src = fs.readFile("src/ReplicatedStorage/" .. k .. ".lua")
	out[k] = luau.load(src, { debugName = k })()
end
-- 稀疏数组（比如挂点 [7]、[8]）的键转成字符串，JSON 才存得下
local function clean(v)
	if type(v) ~= "table" then return v end
	local n, cnt = #v, 0
	for _ in pairs(v) do cnt += 1 end
	local o = {}
	if n > 0 and n == cnt then
		for i = 1, n do o[i] = clean(v[i]) end
	else
		for k, x in pairs(v) do o[tostring(k)] = clean(x) end
	end
	return o
end
fs.writeFile(process.args[1], serde.encode("json", clean(out)))
print("写好了 " .. process.args[1])
