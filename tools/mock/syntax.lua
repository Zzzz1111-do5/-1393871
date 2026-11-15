-- 语法检查：src/ 下每个 .lua 转成 Lua 5.4 后编译一遍；转写后的代码存到临时目录，再用 luacheck.mjs 查未定义的变量
local L = dofile(MOCK_DIR .. "/luau.lua")
local bad, n, edits = 0, 0, 0
LINT_DIR = (os.getenv("TMPDIR") or "/tmp") .. "/ia_lint"
os.execute('rm -rf "' .. LINT_DIR .. '" && mkdir -p "' .. LINT_DIR .. '"')
local p = io.popen('find "' .. SRC_DIR .. '" -name "*.lua" | sort')
for path in p:lines() do
  local f = assert(io.open(path)); local src = f:read("a"); f:close()
  local ok, out, k = pcall(L.compile, src, path)
  if not ok then print("转换失败 " .. tostring(out)); bad = bad + 1
  else
    edits = edits + k
    local fn, err = load(out, "@" .. path, "t", {})
    if not fn then print("编译失败 " .. err); bad = bad + 1 end
    local rel = path:sub(#SRC_DIR + 2):gsub("/", "__")
    local g = assert(io.open(LINT_DIR .. "/" .. rel, "w")); g:write(out); g:close()
  end
  n = n + 1
end
p:close()
print(string.format("%d 个文件，改写复合赋值 %d 处，失败 %d 个", n, edits, bad))
local ok = os.execute('node "' .. MOCK_DIR .. '/luacheck.mjs" "' .. LINT_DIR .. '"')
if not ok then bad = bad + 1 end
TEST_CODE = bad > 0 and 2 or 0
