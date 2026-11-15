-- 开服冒烟：装 src/、跑服务器脚本、一个玩家进服（跑客户端脚本）、推进几十秒，把报错都打出来
local R = dofile(MOCK_DIR .. "/rbx.lua")
local scripts = dofile(MOCK_DIR .. "/load.lua")(R, SRC_DIR)
R.verbose = TEST_ARGS:match("v") ~= nil
for _, s in ipairs(scripts.server) do R.runScript(s, "server") end
R.run(8)
print("开服 8 秒：报错 " .. #R.errors .. "，警告 " .. #R.warns)
local function dump(from)
  for i = from, math.min(from + 9, #R.errors) do print("  " .. R.errors[i]) end
end
dump(1)
local e0 = #R.errors
local p = R.addPlayer("Tester", 1001)
R.localPlayer = p
R.services.Players.PlayerAdded:Fire(p)
for _, c in ipairs(scripts.client) do R.runScript(c, "client") end
R.run(12)
print("玩家进服 12 秒：新增报错 " .. (#R.errors - e0))
dump(e0 + 1)
TEST_CODE = #R.errors > 0 and 2 or 0
print("警告：")
for i = 1, math.min(10, #R.warns) do print("  " .. R.warns[i]:sub(1, 300)) end
