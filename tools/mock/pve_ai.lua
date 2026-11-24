-- PvE 关卡的电脑车辆编成（模拟器；用户 11-24：「做关卡 越多越逼真越好」）：python3 tools/mock/run.py tools/mock/pve_ai.lua [n=6]
--   开第 n 关（默认第 6 关「钢铁洪流」：敌方只开 M1A1 / M1A2、最多 4 辆；友军只开 T-90M / 99A、最多 3 辆）：
--   ① 两边派出来的 AI 车都在这一关点名的型号里；② 同时在场的不超过这一关的 max；③ 16 关都有名字和简报
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check
local N = tonumber(TEST_ARGS:match("n=(%d+)") or "6")

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 120)
G.botsClear()
local L = G.Config.Pve.levels[N]
check(L ~= nil and L.ai ~= nil, "第 " .. N .. " 关有电脑车辆编成")
local Lang = R.require(R.services.ReplicatedStorage:FindFirstChild("Lang"))
local missing = {}
for i = 1, #G.Config.Pve.levels do
  for _, k in ipairs({ "pve.n" .. i, "pve.b" .. i }) do
    local ok, txt = pcall(Lang.t, "zh", k)
    if not ok or txt == nil or txt == k then table.insert(missing, k) end
  end
end
check(#G.Config.Pve.levels >= 16, "关卡 " .. #G.Config.Pve.levels .. " 关")
check(#missing == 0, "每关都有名字和简报（缺：" .. table.concat(missing, "、") .. "）")
-- 这台服务器还没定地图（测试台默认岛）：只有同一张图能直接换关；不是同一张图的关就只测编成函数
T.join("P1", 7002, true)
T.runUntil(function() return G.round and G.round.phase == "battle" end, 120)
G.pveApply(N)
check(G.pve and G.pve.n == N, "换成第 " .. N .. " 关（" .. tostring(G.pve and G.pve.n) .. "）")
G.aiVehOff = false
-- 换关之前（对战的设置）已经派出来的 AI 车收掉：只看换关以后新派的
for _, e in ipairs(G.aiVehicles or {}) do if e.alive then G.removeEnt(e) end end
R.run(0.5)
local seen, maxN = { atk = {}, def = {} }, { atk = 0, def = 0 }
T.runUntil(function()
  local n = { atk = 0, def = 0 }
  for _, e in ipairs(G.aiVehicles or {}) do
    if e.alive then
      n[e.team] = n[e.team] + 1
      seen[e.team][e.def.id] = true
    end
  end
  for t, v in pairs(n) do maxN[t] = math.max(maxN[t], v) end
  return false
end, 70)
for _, team in ipairs({ "def", "atk" }) do
  local a = L.ai[team] or {}
  local ok, list = true, {}
  for id in pairs(seen[team]) do
    table.insert(list, id)
    local hit = false
    for _, x in ipairs(a.ids or {}) do if x == id then hit = true end end
    if a.ids and not hit then ok = false end
  end
  check(#list > 0, team .. " 派出了 AI 车：" .. table.concat(list, "、"))
  check(ok, team .. " 的 AI 车都在这一关点名的型号里（" .. table.concat(a.ids or { "不限" }, "、") .. "）")
  check(maxN[team] <= (a.max or 2), string.format("%s 同时在场最多 %d 辆（这一关 max %d）", team, maxN[team], a.max or 2))
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
