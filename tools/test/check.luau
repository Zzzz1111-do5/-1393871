--!nocheck
-- 语法检查：把 src/ 下所有 .lua 编译一遍（不运行）
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local bad = 0
local function walk(dir)
	for _, n in fs.readDir(dir) do
		local p = dir .. "/" .. n
		if fs.isDir(p) then
			walk(p)
		elseif n:match("%.lua$") then
			local ok, err = pcall(luau.compile, fs.readFile(p))
			if not ok then
				bad += 1
				print("语法错误 " .. p .. "：" .. tostring(err))
			end
		end
	end
end
walk("src")
print(bad == 0 and "语法检查通过" or ("有 " .. bad .. " 个文件语法错误"))
