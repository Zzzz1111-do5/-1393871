-- 语法检查：src/ 下每个 .lua 转成 Lua 5.4 后编译一遍
local L = dofile(MOCK_DIR .. "/luau.lua")
local bad, n, edits = 0, 0, 0
local p = io.popen('find "' .. SRC_DIR .. '" -name "*.lua" | sort')
for path in p:lines() do
  local f = assert(io.open(path)); local src = f:read("a"); f:close()
  local ok, out, k = pcall(L.compile, src, path)
  if not ok then print("转换失败 " .. tostring(out)); bad = bad + 1
  else
    edits = edits + k
    local fn, err = load(out, "@" .. path, "t", {})
    if not fn then print("编译失败 " .. err); bad = bad + 1 end
  end
  n = n + 1
end
p:close()
print(string.format("%d 个文件，改写复合赋值 %d 处，失败 %d 个", n, edits, bad))
TEST_CODE = bad > 0 and 2 or 0
