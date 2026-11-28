-- 选图、换图（模拟器）：python3 tools/mock/run.py tools/mock/mapswitch.lua
--   用户 11-28 晚「然后目前没法切地图」：11-28 一度改成进来二十秒没人投就按默认那张开（钢城），机库里还没去点「这一局」选图图就定了，
--   之后点哪张都换不了（服务器只在开服时建一次图，机库「这一局」那块点别的图「投下一局」这一票什么也不做）。现在：
--   ① 进服、谁也不选：图一直不定（不替人定），机库主按钮是「开战」
--   ② 在「这一局」那块点雪山（投一票）：在场的都投了 → 几秒后开雪山
--   ③ 图定了以后点钢城（换图）：Studio 里不能开新服务器 → 提示「停止后重新开始、进机库先选」，这一局照旧是雪山；
--      线上（G.placeLive）：开一个新服务器（预留服务器），带着要打的图传过去
--   ④ 新服务器那边：进来的人传送数据里带着 map → 直接按那张开（init.server.lua waitMap）——这里换个服务器模拟不了，看投票函数认不认
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R = T.R
local check = T.check
T.mapName = "-"   -- 不定图：走投票
T.mapIds = "city,snow"   -- 两张都能选（11-28 晚起钢城收起来、只剩雪山）
T.wtMode = true
T.matchMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
R.run(0.5)
print("① 进服、谁也不选")
local me = T.join("P1", 9921, true)
local P = G.P[me]
local msgs = {}
local m0 = G.msg
G.msg = function(pl, kind, k, ...)
  if pl == me then table.insert(msgs, k) end
  return m0(pl, kind, k, ...)
end
R.run(40, 1 / 10)
check(G.mapId == nil, "四十秒了图还没定（不替人定：" .. tostring(G.mapId) .. "）")
local S = T.C.S or {}
check(S.phase == "boot" and S.map == nil, "客户端收到的：阶段 " .. tostring(S.phase) .. "、图 " .. tostring(S.map))
print("② 在「这一局」那块点雪山")
T.act("pickMap", "snow")
T.runUntil(function() return G.mapId ~= nil end, 15, 0.25)
check(G.mapId == "snow", "开的是雪山（" .. tostring(G.mapId) .. "）")
R.run(1)
print("③ 图定了以后点钢城（换图）")
msgs = {}
T.act("pickMap", "city")
R.run(1)
local saw = false
for _, k in ipairs(msgs) do if k == "map.switchStudio" then saw = true end end
check(saw, "Studio 里提示停止后重新开始、进机库先选（收到的：" .. table.concat(msgs, ", ") .. "）")
check(G.mapId == "snow", "这一局照旧是雪山")
-- 线上：开新服务器传过去（模拟器的 TeleportService：ReserveServer 给访问码、TeleportAsync 记到 R.teleports，人随后离开这个服务器）
G.placeLive = true
msgs = {}
local n0 = #R.teleports
T.act("pickMap", "city")
R.run(1)
local tp = R.teleports[n0 + 1]
local seen = false
for _, k in ipairs(msgs) do if k == "map.switchNew" then seen = true end end
check(seen, "线上：提示正在开新服务器（" .. table.concat(msgs, ", ") .. "）")
check(tp ~= nil and tp.code ~= "" and type(tp.data) == "table" and tp.data.map == "city",
  string.format("开了预留服务器（访问码 %s）、带着钢城传过去（%s）", tostring(tp and tp.code), tostring(tp and tp.data and tp.data.map)))
G.placeLive = nil
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))
T.summary()
